import Foundation
import Combine
import CoreMIDI

@MainActor
final class MIDIManager: ObservableObject {
    @Published private(set) var destinations: [MIDIDestinationInfo] = []
    @Published private(set) var selectedDestination: MIDIDestinationInfo?
    @Published private(set) var lastSentSnapshot: Int?
    @Published private(set) var lastSentDate: Date?
    @Published private(set) var errorMessage: String?
    private var client: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private let settings: AppSettings

    var isConnected: Bool { selectedDestination != nil && outputPort != 0 }

    init(settings: AppSettings) {
        self.settings = settings
        startClient()
        refreshDestinations()
    }
    deinit {
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }
    private func startClient() {
        if client == 0 {
            let status = MIDIClientCreateWithBlock("TotalMix Snapshot Touch" as CFString, &client) { [weak self] _ in
                DispatchQueue.main.async { self?.refreshDestinations() }
            }
            guard status == noErr else {
                errorMessage = MIDIError.system("MIDI初期化", status).localizedDescription
                return
            }
        }
        if outputPort == 0 {
            let status = MIDIOutputPortCreate(client, "Snapshot Output" as CFString, &outputPort)
            if status != noErr { errorMessage = MIDIError.system("MIDI出力ポート作成", status).localizedDescription }
        }
    }
    func refreshDestinations() {
        if client == 0 || outputPort == 0 { startClient() }
        destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { return nil }
            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
            guard offline == 0 else { return nil }
            let displayName = Self.stringProperty(endpoint, kMIDIPropertyDisplayName)
            let name = displayName.isEmpty ? Self.stringProperty(endpoint, kMIDIPropertyName) : displayName
            return MIDIDestinationInfo(endpoint: endpoint, uniqueID: uniqueID, displayName: name.isEmpty ? "MIDI \(uniqueID)" : name)
        }
        let next = DestinationSelection.preferred(in: destinations, savedID: settings.destinationID)
        if selectedDestination != next { lastSentSnapshot = nil; lastSentDate = nil }
        selectedDestination = next
        if outputPort != 0 { errorMessage = next == nil ? MIDIError.disconnected.localizedDescription : nil }
    }
    func selectDestination(_ destination: MIDIDestinationInfo) {
        guard destinations.contains(destination) else { refreshDestinations(); return }
        settings.destinationID = destination.uniqueID
        selectedDestination = destination
        lastSentSnapshot = nil
        lastSentDate = nil
        errorMessage = nil
    }
    @discardableResult
    func recall(_ number: Int) -> Bool {
        do { try sendSnapshot(number); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func sendSnapshot(_ number: Int) throws {
        let bytes = try SnapshotCommand.bytes(for: number, encoding: settings.encoding)
        guard let destination = selectedDestination, outputPort != 0 else { throw MIDIError.disconnected }
        // Revalidate the endpoint immediately before sending; stale endpoint handles can be reused.
        var uniqueID: Int32 = 0
        var offline: Int32 = 0
        let offlineStatus = MIDIObjectGetIntegerProperty(destination.endpoint, kMIDIPropertyOffline, &offline)
        guard MIDIObjectGetIntegerProperty(destination.endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr,
              uniqueID == destination.uniqueID,
              (offlineStatus == noErr || offlineStatus == kMIDIUnknownProperty),
              offline == 0 else {
            selectedDestination = nil
            lastSentSnapshot = nil
            lastSentDate = nil
            throw MIDIError.disconnected
        }
        var packetList = MIDIPacketList()
        let status = withUnsafeMutablePointer(to: &packetList) { pointer in
            let first = MIDIPacketListInit(pointer)
            return bytes.withUnsafeBufferPointer { buffer in
                _ = MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, first, 0, buffer.count, buffer.baseAddress!)
                return MIDISend(outputPort, destination.endpoint, pointer)
            }
        }
        guard status == noErr else {
            selectedDestination = nil
            lastSentSnapshot = nil
            lastSentDate = nil
            throw MIDIError.system("MIDI送信", status)
        }
        lastSentSnapshot = number
        lastSentDate = Date()
        errorMessage = nil
    }
    private static func stringProperty(_ object: MIDIObjectRef, _ key: CFString) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, key, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }
}
