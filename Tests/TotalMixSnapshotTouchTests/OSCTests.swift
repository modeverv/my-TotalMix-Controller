import XCTest
import Darwin
@testable import TotalMixSnapshotTouch

final class OSCTests: XCTestCase {
    func testWireFormatAndMalformedPackets() {
        let expected: [UInt8] = [47,49,47,109,97,105,110,68,105,109,0,0,44,102,0,0,63,128,0,0]
        let data = OSCMessage.encode("/1/mainDim", value: 1)
        XCTAssertEqual(Array(data), expected)
        XCTAssertEqual(OSCMessage.decode(data), [OSCMessage(address: "/1/mainDim", value: .float(1))])
        for count in 0..<data.count { XCTAssertTrue(OSCMessage.decode(data.prefix(count)).isEmpty) }
        XCTAssertTrue(OSCMessage.decode(OSCMessage.encode("/1/mainDim", value: .nan)).isEmpty)
        var bundle = Data("#bundle\0".utf8) + Data(repeating: 0, count: 8)
        var length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &length) { bundle.append(contentsOf: $0) }
        bundle += data
        XCTAssertEqual(OSCMessage.decode(bundle), OSCMessage.decode(data))
        bundle.removeLast()
        XCTAssertTrue(OSCMessage.decode(bundle).isEmpty)
    }
    @MainActor
    func testFeedbackControlsReconnectAndTimeout() async throws {
        func bindSocket() throws -> (Int32, Int) {
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            XCTAssertEqual(result, 0)
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &address) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
            }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            return (fd, Int(UInt16(bigEndian: address.sin_port)))
        }
        let (server, sendPort) = try bindSocket()
        let (reserved, receivePort) = try bindSocket()
        close(reserved)
        defer { close(server) }
        let suite = "TotalMixOSCTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.oscSendPort = sendPort; settings.oscReceivePort = receivePort
        let manager = OSCManager(settings: settings)
        XCTAssertFalse(manager.canAdjustVolume)
        XCTAssertNil(manager.currentSnapshot)
        XCTAssertFalse(manager.snapshotStateKnown)
        func outgoing() -> [OSCMessage] {
            var result: [OSCMessage] = [], bytes = [UInt8](repeating: 0, count: 65535)
            while true {
                let count = recv(server, &bytes, bytes.count, 0)
                if count <= 0 { break }
                result += OSCMessage.decode(Data(bytes.prefix(count)))
            }
            return result
        }
        XCTAssertFalse(manager.recallSnapshot(1))
        XCTAssertNil(manager.lastSentSnapshot)
        manager.setMainVolume(1, force: true)
        manager.toggleDim(); manager.toggleMuteGroup1()
        XCTAssertEqual(outgoing().map(\.address), ["/3"])
        func feedback(_ path: String, _ value: Float) {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_addr.s_addr = inet_addr("127.0.0.1")
            target.sin_port = UInt16(receivePort).bigEndian
            let data = OSCMessage.encode(path, value: value)
            _ = data.withUnsafeBytes { b in withUnsafePointer(to: &target) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(server, b.baseAddress, b.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }}
        }
        feedback("/1/mainDim", 0); feedback("/3/muteGroups/4/1", 1); feedback("/1/mastervolume", 0.4)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(manager.connected)
        XCTAssertEqual(manager.dim, false); XCTAssertEqual(manager.muteGroup1, true)
        XCTAssertEqual(manager.mainVolume ?? 0, 0.4, accuracy: 0.0001)
        // Check every actual UDP packet, including value 1.0 and reverse row mapping.
        for number in 1...8 { XCTAssertTrue(manager.recallSnapshot(number)) }
        let snapshots = outgoing()
        XCTAssertEqual(snapshots.map(\.address), [
            "/3/snapshots/8/1", "/3/snapshots/7/1", "/3/snapshots/6/1", "/3/snapshots/5/1",
            "/3/snapshots/4/1", "/3/snapshots/3/1", "/3/snapshots/2/1", "/3/snapshots/1/1"
        ])
        XCTAssertTrue(snapshots.allSatisfy { $0.value == .float(1) })
        XCTAssertEqual(manager.lastSentSnapshot, 8)
        XCTAssertNil(manager.currentSnapshot) // Sending is not confirmation.
        XCTAssertNotNil(manager.lastSentDate)
        settings.setHidden(true, for: 2)
        XCTAssertFalse(manager.recallSnapshot(2))
        XCTAssertFalse(manager.recallSnapshot(0))
        XCTAssertFalse(manager.recallSnapshot(9))
        XCTAssertTrue(outgoing().isEmpty)
        XCTAssertEqual(manager.lastSentSnapshot, 8)
        // External recall updates selection even for hidden snapshots, not last-sent history.
        for number in 1...8 {
            feedback(SnapshotCommand.address(for: number)!, 1)
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(manager.currentSnapshot, number)
            XCTAssertTrue(manager.snapshotStateKnown)
        }
        feedback("/3/snapshots/8/1", 1) // Snapshot 1 becomes selected.
        feedback("/3/snapshots/1/1", 0) // Late deselection of Snapshot 8 must not clear 1.
        feedback("/3/snapshots/9/1", 1) // Invalid address.
        feedback("/3/snapshots/2/1", 0.5) // Invalid state.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(manager.currentSnapshot, 1)
        XCTAssertEqual(manager.lastSentSnapshot, 8)
        feedback("/3/snapshots/8/1", 0) // Edited mix / no active snapshot.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(manager.currentSnapshot)
        XCTAssertTrue(manager.snapshotStateKnown)
        manager.toggleDim(); manager.toggleDim() // No double toggle before feedback.
        manager.toggleMuteGroup1(); manager.setMainVolume(0.3, force: true)
        XCTAssertEqual(outgoing().map(\.address), ["/1/mainDim", "/3/muteGroups/4/1", "/1/mastervolume"])
        XCTAssertEqual(manager.dim, false) // Never invent an acknowledged ON state.
        manager.reconnect()
        XCTAssertNil(manager.errorMessage)
        XCTAssertNil(manager.lastSentSnapshot)
        XCTAssertNil(manager.lastSentDate)
        XCTAssertNil(manager.currentSnapshot)
        XCTAssertFalse(manager.snapshotStateKnown)
        XCTAssertFalse(manager.connected)
        feedback("/1/mastervolume", 0.3)
        feedback("/3/snapshots/2/1", 1)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(manager.canAdjustVolume)
        XCTAssertEqual(manager.currentSnapshot, 7)
        try await Task.sleep(nanoseconds: 4_800_000_000)
        XCTAssertFalse(manager.connected)
        XCTAssertFalse(manager.canAdjustVolume)
        XCTAssertNil(manager.currentSnapshot)
        XCTAssertFalse(manager.snapshotStateKnown)
        XCTAssertFalse(manager.recallSnapshot(1))
        settings.oscEnabled = false; manager.reconnect()
        XCTAssertFalse(manager.recallSnapshot(1))
    }
}
