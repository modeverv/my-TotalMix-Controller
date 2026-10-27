import XCTest
@testable import TotalMixSnapshotTouch

final class SnapshotTests: XCTestCase {
    @MainActor
    func testIPv4HostValidationAndPersistence() async throws {
        let suite = "TotalMixHostTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #if os(iOS)
        XCTAssertEqual(settings.oscHost, "")
        XCTAssertEqual(settings.oscSendPort, 7002)
        XCTAssertEqual(settings.oscReceivePort, 9002)
        #else
        XCTAssertEqual(settings.oscHost, "127.0.0.1")
        XCTAssertEqual(settings.oscSendPort, 7001)
        XCTAssertEqual(settings.oscReceivePort, 9001)
        #endif
        settings.oscHost = "192.168.1.25"
        XCTAssertEqual(AppSettings(defaults: defaults).oscHost, "192.168.1.25")
        for host in ["127.0.0.1", "192.168.1.25", " 10.0.0.2 "] {
            XCTAssertNotNil(OSCManager.ipv4Address(for: host), host)
        }
        for host in ["", "localhost", "192.168.1.999", "::1", "0.0.0.0", "0.1.2.3", "224.0.0.1", "255.255.255.255", "192.168.1.2:7002"] {
            XCTAssertNil(OSCManager.ipv4Address(for: host), host)
        }
    }

    func testSnapshotAddresses() {
        XCTAssertEqual((1...8).compactMap { SnapshotCommand.address(for: $0) }, [
            "/3/snapshots/8/1", "/3/snapshots/7/1", "/3/snapshots/6/1", "/3/snapshots/5/1",
            "/3/snapshots/4/1", "/3/snapshots/3/1", "/3/snapshots/2/1", "/3/snapshots/1/1"
        ])
        XCTAssertNil(SnapshotCommand.address(for: 0))
        XCTAssertNil(SnapshotCommand.address(for: 9))
    }
    @MainActor
    func testExistingSettingsSurviveOSCOnlyMigration() async throws {
        let suite = "TotalMixTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Legacy keys must not interfere with names, visibility, or the OSC connection.
        defaults.set(-123, forKey: "destinationUniqueID")
        defaults.set("noteOnZero", forKey: "midiEncoding")
        defaults.set([2, 3, 4, 5, 6, 8], forKey: "hiddenSnapshots")
        defaults.set(7101, forKey: "oscSendPort")
        defaults.set(9101, forKey: "oscReceivePort")
        let first = AppSettings(defaults: defaults)
        for number in 1...8 { first.setName("名前 \(number)", for: number) }
        let next = AppSettings(defaults: defaults)
        for number in 1...8 { XCTAssertEqual(next.name(for: number), "名前 \(number)") }
        XCTAssertEqual(next.visibleSnapshotNumbers, [1, 7])
        XCTAssertEqual(next.oscSendPort, 7101)
        XCTAssertEqual(next.oscReceivePort, 9101)
        next.setHidden(false, for: 2)
        XCTAssertEqual(AppSettings(defaults: defaults).visibleSnapshotNumbers, [1, 2, 7])
        next.setName("  ", for: 1)
        XCTAssertEqual(next.name(for: 1), "Snapshot 1")
        next.resetNames()
        XCTAssertEqual(AppSettings(defaults: defaults).snapshotNames, (1...8).map { "Snapshot \($0)" })
        XCTAssertEqual(AppSettings(defaults: defaults).visibleSnapshotNumbers, [1, 2, 7])
    }
}
