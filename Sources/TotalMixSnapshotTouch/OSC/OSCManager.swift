import Foundation
import Combine
import Darwin

/// Feedback-driven TotalMix OSC controller: loopback on Mac, configured IPv4 host on iOS.
@MainActor
final class OSCManager: ObservableObject {
    @Published private(set) var currentSnapshot: Int?
    @Published private(set) var snapshotStateKnown = false
    @Published private(set) var lastSentSnapshot: Int?
    @Published private(set) var lastSentDate: Date?
    @Published private(set) var muteGroup1: Bool?
    @Published private(set) var dim: Bool?
    @Published private(set) var mainVolume: Double?
    @Published private(set) var volumeLabel = "— dB"
    @Published private(set) var connected = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingMute = false
    @Published private(set) var pendingDim = false
    private var socketFD: Int32 = -1
    private var reader: DispatchSourceRead?
    private var timer: Timer?
    private var closingSocket = false
    private var pendingReconnect = false
    private var lastSnapshotFeedback = Date.distantPast
    private var lastFeedback = Date.distantPast
    private var lastVolumeFeedback = Date.distantPast
    private var lastMuteFeedback = Date.distantPast
    private var lastDimFeedback = Date.distantPast
    private var lastVolumeSend = Date.distantPast
    private var muteSent = Date.distantPast
    private var dimSent = Date.distantPast
    private var page = 1
    private let settings: AppSettings
    private var destination = sockaddr_in()
    var canAdjustVolume: Bool { connected && mainVolume != nil }

    init(settings: AppSettings) { self.settings = settings; reconnect() }
    deinit { timer?.invalidate(); reader?.cancel() }

    func reconnect() {
        disconnect()
        pendingReconnect = true
        if !closingSocket { pendingReconnect = false; openSocket() }
    }

    /// Forget live mixer state when the app leaves the foreground. Nothing is restored on resume.
    func disconnect() {
        pendingReconnect = false
        timer?.invalidate(); timer = nil
        if let source = reader {
            let oldFD = socketFD
            reader = nil; socketFD = -1
            closingSocket = true
            // Dispatch owns the descriptor until cancellation has completed. Opening the new
            // socket afterward also prevents a same-port reconnect from failing spuriously.
            source.setCancelHandler { [weak self] in
                Darwin.close(oldFD)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.closingSocket = false
                    if self.pendingReconnect {
                        self.pendingReconnect = false
                        self.openSocket()
                    }
                }
            }
            source.cancel()
        }
        resetFeedback()
        errorMessage = nil
    }

    /// Only literal unicast IPv4 addresses are accepted; no DNS lookup blocks the UI.
    static func ipv4Address(for host: String) -> in_addr? {
        var address = in_addr()
        guard inet_pton(AF_INET, host.trimmingCharacters(in: .whitespacesAndNewlines), &address) == 1 else { return nil }
        let firstOctet = UInt32(bigEndian: address.s_addr) >> 24
        guard firstOctet > 0, firstOctet < 224 else { return nil }
        return address
    }

    private func openSocket() {
        guard settings.oscEnabled else { return }
        #if os(iOS)
        let host = settings.oscHost
        #else
        // Existing Mac installs retain their original loopback-only behavior.
        let host = "127.0.0.1"
        #endif
        guard let remoteAddress = Self.ipv4Address(for: host) else {
            errorMessage = "TotalMixが動いているMacのIPv4アドレスを設定してください。"; return
        }
        guard (1024...65535).contains(settings.oscSendPort), (1024...65535).contains(settings.oscReceivePort), settings.oscSendPort != settings.oscReceivePort else {
            errorMessage = "異なる送信・受信ポートを1024〜65535で指定してください。"; return
        }
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { errorMessage = "OSCソケットを作成できません。"; return }
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = UInt16(settings.oscReceivePort).bigEndian
        #if os(iOS)
        local.sin_addr.s_addr = INADDR_ANY
        #else
        local.sin_addr.s_addr = inet_addr("127.0.0.1")
        #endif
        let result = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else {
            Darwin.close(fd)
            errorMessage = "OSC受信ポート \(settings.oscReceivePort) を開けません。他の起動中アプリやポート設定を確認してください。"
            return
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        destination = local
        destination.sin_addr = remoteAddress
        destination.sin_port = UInt16(settings.oscSendPort).bigEndian
        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.socketFD == fd else { return }
            self.receive()
        }
        source.setCancelHandler { Darwin.close(fd) }
        reader = source; source.resume()
        // Page requests contain no mixer command and never restore a previous volume.
        requestPage()
        let feedbackTimer = Timer(timeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = feedbackTimer
        // Scrolling or dragging an iPhone fader must not pause feedback expiry checks.
        RunLoop.main.add(feedbackTimer, forMode: .common)
    }
    private func resetFeedback() {
        currentSnapshot = nil; snapshotStateKnown = false; lastSnapshotFeedback = .distantPast
        lastSentSnapshot = nil; lastSentDate = nil
        connected = false; muteGroup1 = nil; dim = nil; mainVolume = nil
        volumeLabel = "— dB"; pendingMute = false; pendingDim = false
        lastFeedback = .distantPast; lastVolumeFeedback = .distantPast
        lastMuteFeedback = .distantPast; lastDimFeedback = .distantPast
        lastVolumeSend = .distantPast; muteSent = .distantPast; dimSent = .distantPast
    }
    private func tick() {
        if Date().timeIntervalSince(lastFeedback) > 4 { resetFeedback() }
        if Date().timeIntervalSince(lastSnapshotFeedback) > 4 { currentSnapshot = nil; snapshotStateKnown = false }
        if Date().timeIntervalSince(lastVolumeFeedback) > 4 { mainVolume = nil; volumeLabel = "— dB" }
        if Date().timeIntervalSince(lastMuteFeedback) > 4 { muteGroup1 = nil }
        if Date().timeIntervalSince(lastDimFeedback) > 4 { dim = nil }
        if pendingMute && Date().timeIntervalSince(muteSent) > 2 { pendingMute = false; muteGroup1 = nil }
        if pendingDim && Date().timeIntervalSince(dimSent) > 2 { pendingDim = false; dim = nil }
        requestPage()
    }
    private func requestPage() {
        page = page == 1 ? 3 : 1
        send("/\(page)", value: 0)
    }
    @discardableResult
    func recallSnapshot(_ number: Int) -> Bool {
        guard connected, !settings.hiddenSnapshots.contains(number),
              let address = SnapshotCommand.address(for: number) else { return false }
        guard send(address, value: 1) else { return false }
        lastSentSnapshot = number
        lastSentDate = Date()
        return true
    }
    func toggleMuteGroup1() {
        guard connected, muteGroup1 != nil, !pendingMute else { return }
        muteSent = Date(); pendingMute = true
        if !send("/3/muteGroups/4/1", value: 1) { pendingMute = false }
    }
    func toggleDim() {
        guard connected, dim != nil, !pendingDim else { return }
        dimSent = Date(); pendingDim = true
        if !send("/1/mainDim", value: 1) { pendingDim = false }
    }
    func setMainVolumeToZeroDB() {
        // RME's OSC fader curve: 0 dB is approximately 0.8172, not 1.0 (+6 dB).
        let unityPosition = (26.8235294118 / 0.0320855615) / 1023.0
        // Round upward by one Float ULP to avoid TotalMix displaying negative zero.
        setMainVolume(Double(Float(unityPosition).nextUp), force: true)
    }
    func setMainVolume(_ value: Double, force: Bool = false) {
        guard canAdjustVolume, value.isFinite else { return }
        guard force || Date().timeIntervalSince(lastVolumeSend) >= 1.0 / 30 else { return }
        lastVolumeSend = Date()
        send("/1/mastervolume", value: Float(min(1, max(0, value))))
    }
    @discardableResult
    private func send(_ address: String, value: Float) -> Bool {
        guard socketFD >= 0 else { return false }
        let data = OSCMessage.encode(address, value: value)
        let count = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if count != data.count { errorMessage = "OSC送信に失敗しました。再接続してください。"; return false }
        return true
    }
    private func receive() {
        guard socketFD >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 65535)
        // Keep UI responsive even if a sender floods this port.
        for _ in 0..<64 {
            var source = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketFD, &bytes, bytes.count, 0, $0, &length)
                }
            }
            guard count > 0 else { return }
            guard source.sin_family == sa_family_t(AF_INET),
                  source.sin_addr.s_addr == destination.sin_addr.s_addr else { continue }
            for message in OSCMessage.decode(Data(bytes.prefix(count))) {
                switch message.address {
                case "/3/muteGroups/4/1":
                    guard let value = message.number, value == 0 || value == 1 else { continue }
                    muteGroup1 = value != 0; lastMuteFeedback = Date(); pendingMute = false
                case "/1/mainDim":
                    guard let value = message.number, value == 0 || value == 1 else { continue }
                    dim = value != 0; lastDimFeedback = Date(); pendingDim = false
                case "/1/mastervolume":
                    guard let value = message.number, (0...1).contains(value) else { continue }
                    mainVolume = Double(value); lastVolumeFeedback = Date()
                case "/1/mastervolumeVal":
                    guard case .string(let label) = message.value else { continue }
                    volumeLabel = label
                default:
                    guard let number = SnapshotCommand.number(forFeedbackAddress: message.address),
                          let value = message.number, value == 0 || value == 1 else { continue }
                    if value == 1 { currentSnapshot = number }
                    else if currentSnapshot == number { currentSnapshot = nil }
                    snapshotStateKnown = true
                    lastSnapshotFeedback = Date()
                }
                lastFeedback = Date(); connected = true; errorMessage = nil
            }
        }
    }
}
