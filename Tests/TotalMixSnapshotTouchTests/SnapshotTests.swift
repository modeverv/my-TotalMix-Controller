import XCTest
import CoreMIDI
@testable import TotalMixSnapshotTouch

final class SnapshotTests: XCTestCase {
    func testAllSnapshotBytesAndInvalidNumbers() throws {
        for number in 1...8 {
            XCTAssertEqual(try SnapshotCommand.bytes(for: number), [0x80, UInt8(53 + number), 0])
            XCTAssertEqual(try SnapshotCommand.bytes(for: number, encoding: .noteOnZero), [0x90, UInt8(53 + number), 0])
        }
        XCTAssertThrowsError(try SnapshotCommand.bytes(for: 0))
        XCTAssertThrowsError(try SnapshotCommand.bytes(for: 9))
    }
    func testDestinationSelectionPriorityAndMissingPort() {
        let named = MIDIDestinationInfo(endpoint: 1, uniqueID: 10, displayName: "IAC TotalMixRemote")
        let chosen = MIDIDestinationInfo(endpoint: 2, uniqueID: 20, displayName: "Other")
        XCTAssertEqual(DestinationSelection.preferred(in: [named, chosen], savedID: 20), chosen)
        XCTAssertEqual(DestinationSelection.preferred(in: [named, chosen], savedID: 99), named)
        XCTAssertEqual(DestinationSelection.preferred(in: [named], savedID: nil), named)
        XCTAssertNil(DestinationSelection.preferred(in: [chosen], savedID: nil))
        XCTAssertNil(DestinationSelection.preferred(in: [], savedID: 20))
    }
    @MainActor
    func testSettingsSurviveReloadAndReset() async throws {
        let suite = "TotalMixTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppSettings(defaults: defaults)
        for number in 1...8 { first.setName("名前 \(number)", for: number) }
        first.destinationID = -123
        first.encoding = .noteOnZero
        let next = AppSettings(defaults: defaults)
        for number in 1...8 { XCTAssertEqual(next.name(for: number), "名前 \(number)") }
        XCTAssertEqual(next.destinationID, -123)
        XCTAssertEqual(next.encoding, .noteOnZero)
        next.setName("  ", for: 1)
        XCTAssertEqual(next.name(for: 1), "Snapshot 1")
        next.resetNames()
        XCTAssertEqual(AppSettings(defaults: defaults).snapshotNames, (1...8).map { "Snapshot \($0)" })
    }
    @MainActor
    func testCoreMIDISendsToIsolatedEndpointAndHandlesRemoval() async throws {
        let suite = "TotalMixTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var client: MIDIClientRef = 0
        var endpoint: MIDIEndpointRef = 0
        XCTAssertEqual(MIDIClientCreateWithBlock("Snapshot Tests" as CFString, &client, nil), noErr)
        defer { MIDIClientDispose(client) }
        let received = expectation(description: "Eight Note Off messages and compatibility message")
        received.expectedFulfillmentCount = 9
        let collector = PacketCollector()
        XCTAssertEqual(MIDIDestinationCreateWithBlock(client, "Isolated Snapshot Test" as CFString, &endpoint) { list, _ in
            var pointer = UnsafeRawPointer(list).advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!).assumingMemoryBound(to: MIDIPacket.self)
            for index in 0..<list.pointee.numPackets {
                let packet = pointer.pointee
                let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
                // CoreMIDI may coalesce several three-byte messages into one packet.
                for start in stride(from: 0, to: bytes.count, by: 3) {
                    collector.append(Array(bytes[start..<min(start + 3, bytes.count)]))
                    received.fulfill()
                }
                if index + 1 < list.pointee.numPackets { pointer = UnsafePointer(MIDIPacketNext(pointer)) }
            }
        }, noErr)
        var uniqueID: Int32 = 0
        XCTAssertEqual(MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID), noErr)
        let settings = AppSettings(defaults: defaults)
        settings.destinationID = uniqueID
        let manager = MIDIManager(settings: settings)
        XCTAssertEqual(manager.selectedDestination?.endpoint, endpoint)
        for number in 1...8 { try manager.sendSnapshot(number) }
        settings.encoding = .noteOnZero
        try manager.sendSnapshot(1)
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(collector.all(), (1...8).map { [UInt8(0x80), UInt8(53 + $0), UInt8(0)] } + [[0x90, 54, 0]])
        XCTAssertEqual(manager.lastSentSnapshot, 1)
        XCTAssertEqual(MIDIEndpointDispose(endpoint), noErr)
        // No refresh in between: exercise stale handle validation, never send to a real IAC endpoint.
        XCTAssertFalse(manager.recall(2))
        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(manager.lastSentSnapshot)
        XCTAssertNotNil(manager.errorMessage)
    }
}

private final class PacketCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [[UInt8]] = []
    func append(_ bytes: [UInt8]) { lock.lock(); defer { lock.unlock() }; packets.append(bytes) }
    func all() -> [[UInt8]] { lock.lock(); defer { lock.unlock() }; return packets }
}
