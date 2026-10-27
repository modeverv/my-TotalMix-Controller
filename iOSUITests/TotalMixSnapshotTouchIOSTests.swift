import XCTest
import Darwin

/// Exercises the real app against a local OSC peer, without touching TotalMix.
final class TotalMixSnapshotTouchIOSTests: XCTestCase {
    private var app: XCUIApplication!
    private var peer: OSCUITestPeer?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = [
            "UITEST_OSC_HOST": "127.0.0.1",
            "UITEST_OSC_SEND_PORT": "17002",
            "UITEST_OSC_RECEIVE_PORT": "19002"
        ]
    }

    override func tearDownWithError() throws {
        app.terminate()
        peer?.stop()
        peer = nil
    }

    func testFeedbackCommandsAndTimeout() throws {
        let peer = try OSCUITestPeer()
        self.peer = peer
        app.launch()
        let first = app.buttons["snapshot.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        waitUntil { first.isEnabled }
        waitUntil { (first.value as? String) == "選択中" }
        // Connecting and polling must never change the mix.
        XCTAssertTrue(peer.commands.isEmpty)

        let seventh = app.buttons["snapshot.7"]
        reveal(seventh)
        seventh.tap()
        waitUntil { peer.commands.contains("/3/snapshots/2/1") }
        waitUntil { (seventh.value as? String) == "選択中" }
        attachScreenshot("iphone-connected-snapshots")

        let mute = app.buttons["monitor.mute"]
        reveal(mute)
        mute.tap()
        waitUntil { peer.commands.contains("/3/muteGroups/4/1") }
        app.buttons["monitor.dim"].tap()
        waitUntil { peer.commands.contains("/1/mainDim") }
        app.buttons["monitor.unity"].tap()
        waitUntil { peer.commands.contains("/1/mastervolume") }
        let slider = app.sliders["monitor.volume"]
        reveal(slider)
        XCTAssertTrue(slider.isEnabled)
        waitUntil { self.app.staticTexts["volumeLabel"].label == "-12.0 dB" }
        slider.adjust(toNormalizedSliderPosition: 0.3)
        waitUntil { peer.volumeCommands.count >= 2 }
        XCTAssertTrue(peer.volumeCommands.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertTrue(peer.volumeCommands.contains { abs($0 - 0.8172) < 0.001 })
        attachScreenshot("iphone-connected-monitor")

        peer.responds = false
        waitUntil(timeout: 8) { !mute.isEnabled && !slider.isEnabled }
        reveal(first, upwards: false)
        XCTAssertFalse(first.isEnabled)
        XCTAssertNotEqual(first.value as? String, "選択中")
        attachScreenshot("iphone-offline")
    }

    func testSettingsAndHiddenSnapshotRecoveryWhileOffline() throws {
        app.launch()
        XCTAssertTrue(app.buttons["snapshot.1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["snapshot.1"].isEnabled)
        app.buttons["settings.open"].tap()
        let host = app.textFields["settings.host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertEqual(host.value as? String, "127.0.0.1")
        attachScreenshot("iphone-settings")

        for number in 1...8 {
            let toggle = app.switches["settings.hide.\(number)"]
            setSwitch(toggle, to: true)
        }
        app.buttons["settings.done"].tap()
        XCTAssertFalse(app.buttons["snapshot.1"].exists)
        let recover = app.buttons["restoreSnapshotsButton"]
        XCTAssertTrue(recover.waitForExistence(timeout: 5))
        recover.tap()
        let firstToggle = app.switches["settings.hide.1"]
        // A newly presented Form may restore its previous scroll position.
        let hostAgain = app.textFields["settings.host"]
        reveal(hostAgain, upwards: false)
        setSwitch(firstToggle, to: false)
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["snapshot.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["snapshot.2"].exists)
    }

    private func setSwitch(_ element: XCUIElement, to enabled: Bool) {
        reveal(element)
        let expected = enabled ? "1" : "0"
        guard (element.value as? String) != expected else { return }
        // SwiftUI exposes the Toggle label and native switch as one wide AX
        // element. Tap the trailing switch control rather than the row center.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitUntil { (element.value as? String) == expected }
    }

    private func reveal(_ element: XCUIElement, upwards: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        // Short overlapping swipes avoid skipping a Form row and do not drag the
        // horizontal volume slider. They also work when lazy rows do not exist yet.
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: upwards ? 0.78 : 0.35))
            let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: upwards ? 0.35 : 0.78))
            start.press(forDuration: 0.02, thenDragTo: finish)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element.identifier)", file: file, line: line)
    }

    private func waitUntil(timeout: TimeInterval = 6, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class OSCUITestPeer {
    private let fd: Int32
    private let queue = DispatchQueue(label: "totalmix.ios-uitest.osc")
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var recorded: [(String, Float)] = []
    private var shouldRespond = true
    private var selected = 1
    private var muted = false
    private var dimmed = false
    private var volume: Float = 0.5

    var commands: [String] { lock.lock(); defer { lock.unlock() }; return recorded.map { $0.0 } }
    var volumeCommands: [Float] { lock.lock(); defer { lock.unlock() }; return recorded.filter { $0.0 == "/1/mastervolume" }.map { $0.1 } }
    var responds: Bool {
        get { lock.lock(); defer { lock.unlock() }; return shouldRespond }
        set { lock.lock(); shouldRespond = newValue; lock.unlock() }
    }

    init() throws {
        fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(17002).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.receive() }
        let descriptor = fd
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        queue.sync { }
    }

    deinit { stop() }

    private func receive() {
        var bytes = [UInt8](repeating: 0, count: 2048)
        while true {
            let count = recv(fd, &bytes, bytes.count, 0)
            guard count > 0 else { return }
            let packet = Array(bytes.prefix(count))
            guard let end = packet.firstIndex(of: 0), let address = String(bytes: packet[..<end], encoding: .utf8) else { continue }
            let valueOffset = ((end + 4) / 4) * 4 + 4
            let value: Float
            if packet.count >= valueOffset + 4 {
                let raw = packet[valueOffset..<valueOffset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                value = Float(bitPattern: raw)
            } else { value = 0 }
            if address != "/1" && address != "/3" {
                lock.lock(); recorded.append((address, value)); lock.unlock()
                if address == "/3/muteGroups/4/1" { muted.toggle() }
                if address == "/1/mainDim" { dimmed.toggle() }
                if address == "/1/mastervolume" { volume = value }
                if address.hasPrefix("/3/snapshots/"), let row = Int(address.split(separator: "/")[2]) { selected = 9 - row }
            }
            guard responds else { continue }
            send("/3/snapshots/\(9 - selected)/1", value: selected > 0 ? 1 : 0)
            send("/3/muteGroups/4/1", value: muted ? 1 : 0)
            send("/1/mainDim", value: dimmed ? 1 : 0)
            send("/1/mastervolume", value: volume)
            // A fixed display label is sufficient to exercise OSC string feedback;
            // this peer does not reproduce TotalMix's nonlinear fader curve.
            send("/1/mastervolumeVal", label: "-12.0 dB")
        }
    }

    private func send(_ address: String, value: Float) {
        var data = padded(address) + padded(",f")
        let bits = value.bitPattern
        data += [UInt8(truncatingIfNeeded: bits >> 24), UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 8), UInt8(truncatingIfNeeded: bits)]
        sendPacket(data)
    }

    private func send(_ address: String, label: String) {
        sendPacket(padded(address) + padded(",s") + padded(label))
    }

    private func padded(_ string: String) -> [UInt8] {
        var bytes = Array(string.utf8) + [0]
        while bytes.count % 4 != 0 { bytes.append(0) }
        return bytes
    }

    private func sendPacket(_ data: [UInt8]) {
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_addr.s_addr = inet_addr("127.0.0.1")
        target.sin_port = UInt16(19002).bigEndian
        _ = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
    }
}
