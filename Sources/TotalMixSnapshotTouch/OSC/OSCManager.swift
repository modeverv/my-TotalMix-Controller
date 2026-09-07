import Foundation
import Combine
import Darwin

/// One local TotalMix OSC controller, with state feedback. No Internet/LAN endpoint is used.
@MainActor
final class OSCManager: ObservableObject {
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
    deinit { timer?.invalidate(); reader?.cancel(); if socketFD >= 0 { Darwin.close(socketFD) } }

    func reconnect() {
        timer?.invalidate(); timer = nil
        reader?.cancel(); reader = nil
        if socketFD >= 0 { Darwin.close(socketFD) }; socketFD = -1
        resetFeedback()
        errorMessage = nil
        guard settings.oscEnabled else { return }
        guard (1024...65535).contains(settings.oscSendPort), (1024...65535).contains(settings.oscReceivePort), settings.oscSendPort != settings.oscReceivePort else {
            errorMessage = "異なる送信・受信ポートを1024〜65535で指定してください。"; return
        }
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { errorMessage = "OSCソケットを作成できません。"; return }
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = UInt16(settings.oscReceivePort).bigEndian
        local.sin_addr.s_addr = inet_addr("127.0.0.1")
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
        destination.sin_port = UInt16(settings.oscSendPort).bigEndian
        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.receive() }
        reader = source; source.resume()
        // Page requests contain no mixer command and never restore a previous volume.
        requestPage()
        timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func resetFeedback() {
        lastSentSnapshot = nil; lastSentDate = nil
        connected = false; muteGroup1 = nil; dim = nil; mainVolume = nil
        volumeLabel = "— dB"; pendingMute = false; pendingDim = false
        lastFeedback = .distantPast; lastVolumeFeedback = .distantPast
        lastMuteFeedback = .distantPast; lastDimFeedback = .distantPast
    }
    private func tick() {
        if Date().timeIntervalSince(lastFeedback) > 4 { resetFeedback() }
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
        // Keep UI responsive even if a sender floods this local port.
        for _ in 0..<64 {
            var source = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketFD, &bytes, bytes.count, 0, $0, &length)
                }
            }
            guard count > 0 else { return }
            guard source.sin_addr.s_addr == inet_addr("127.0.0.1") else { continue }
            for message in OSCMessage.decode(Data(bytes.prefix(count))) {
                switch message.address {
                case "/3/muteGroups/4/1":
                    if let value = message.number {
                        muteGroup1 = value != 0; lastMuteFeedback = Date(); pendingMute = false
                    }
                case "/1/mainDim":
                    if let value = message.number {
                        dim = value != 0; lastDimFeedback = Date(); pendingDim = false
                    }
                case "/1/mastervolume":
                    if let value = message.number, (0...1).contains(value) {
                        mainVolume = Double(value); lastVolumeFeedback = Date()
                    }
                case "/1/mastervolumeVal":
                    if case .string(let label) = message.value { volumeLabel = label }
                default: continue
                }
                lastFeedback = Date(); connected = true; errorMessage = nil
            }
        }
    }
}
