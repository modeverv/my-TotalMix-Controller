import XCTest
@testable import TotalMixSnapshotTouch

final class SnapshotTests: XCTestCase {
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
