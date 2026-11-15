import XCTest

/// The guide's long-press menu on iPhone and iPad (guide-long-press-record 1.3) on the demo
/// server: without a server the running show offers Watch Channel and Details only; with a paired
/// Fernsy Server (the dev services, as `ServerUITests`; skipped without them) the running show can
/// be ordered there and the order taken back from the same menu; Details opens a later show's sheet.
final class GuideLongPressUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ env: [String: String] = [:], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
            "IPTV_TAB": "live",
            "IPTV_LIVEVIEW": "guide",
        ].merging(env) { $1 }
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "de" ? "de_DE" : "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    /// Channel 101's cells, by start (from their identifiers `guide.101.<start epoch>`), looked up
    /// by identifier: an element by index goes stale once the guide scrolls.
    private func cells(_ app: XCUIApplication) -> [(start: Int, element: XCUIElement)] {
        let query = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.101.' AND NOT (identifier CONTAINS '.gap.')"))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 30), "no listings in the guide:\n\(app.debugDescription)")
        return query.allElementsBoundByIndex
            .compactMap { cell in Int(cell.identifier.split(separator: ".").last ?? "").map { ($0, app.buttons[cell.identifier]) } }
            .sorted { $0.start < $1.start }
    }

    /// The show of channel 101 that runs now.
    private func running(_ app: XCUIApplication) throws -> XCUIElement {
        // The row may still hold only part of its listings: wait for a show that began before now
        // and is followed by one that begins after.
        let deadline = Date().addingTimeInterval(20)
        repeat {
            let now = Int(Date().timeIntervalSince1970)
            let all = cells(app)
            if let index = all.lastIndex(where: { $0.start <= now }), index + 1 < all.count { return all[index].element }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        throw XCTSkip("no running show of channel 101 in the guide")
    }

    /// Scrolls the guide sideways until part of `cell` is on screen, then long-presses that part.
    private func longPress(_ cell: XCUIElement, _ app: XCUIApplication) {
        let window = app.windows.firstMatch
        // Right of the pinned channel column.
        let left = window.frame.minX + 100, right = window.frame.maxX - 20
        for _ in 0..<6 {
            let frame = cell.frame
            if frame.maxX > left + 40 && frame.minX < right - 40 { break }
            let y = frame.midY / window.frame.height
            // A cell left of the screen comes in with a drag to the right, one on the right with a drag to the left.
            let (from, to): (CGFloat, CGFloat) = frame.maxX <= left + 40 ? (0.45, 0.8) : (0.8, 0.45)
            window.coordinate(withNormalizedOffset: CGVector(dx: from, dy: y))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: to, dy: y)))
        }
        let frame = cell.frame
        let x = (max(frame.minX, left) + min(frame.maxX, right)) / 2
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: frame.midY)).press(forDuration: 1.2)
    }

    private func waitForState(_ app: XCUIApplication, _ value: String, timeout: TimeInterval = 20) -> Bool {
        let state = app.descendants(matching: .any)["player.state"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state.exists, (state.value as? String) == value { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// (a) No server: Watch Channel and Details, nothing about recording; Watch Channel plays.
    func testRunningShowWithoutAServer() throws {
        // No cloud account in the test (no keychain), so no server.
        let app = launch()
        let show = try running(app)
        longPress(show, app)
        let watch = app.buttons["Watch Channel"]
        XCTAssertTrue(watch.waitForExistence(timeout: 5), "no menu with Watch Channel:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Details"].exists, "no Details in the menu")
        XCTAssertFalse(app.buttons["Record on Fernsy Server"].exists, "a recording item without a server")
        shot("menu-running-no-server", app)
        watch.tap()
        XCTAssertTrue(waitForState(app, "playing"), "Watch Channel did not play the channel")
    }

    /// (b) Paired server: the running show is ordered from the menu and marked; the menu then
    /// offers Cancel Recording, which removes the order and the mark.
    func testRunningShowOnTheServer() throws {
        guard let env = ServerUITests.pairedEnv else { throw XCTSkip("no paired Fernsy Server and dev services in the test environment") }
        let app = launch(env)
        let show = try running(app)
        // The server's state is read a moment after launch.
        Thread.sleep(forTimeInterval: 5)
        longPress(show, app)
        let record = app.buttons["Record on Fernsy Server"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "no Record on Fernsy Server in the menu:\n\(app.debugDescription)")
        shot("menu-running-server", app)
        record.tap()
        expectation(for: NSPredicate(format: "value == 'server'"), evaluatedWith: show)
        waitForExpectations(timeout: 20)
        shot("running-ordered", app)

        longPress(show, app)
        let cancel = app.buttons["Cancel Recording"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "no Cancel Recording in the menu:\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Record on Fernsy Server"].exists, "both Record and Cancel in the menu")
        cancel.tap()
        expectation(for: NSPredicate(format: "value != 'server'"), evaluatedWith: show)
        waitForExpectations(timeout: 20)
    }

    /// (d) The account's only stream is in use: ordering the running show from the menu is
    /// refused with its reason, and the show gets no mark. The simulator has no Picture in
    /// Picture, so the stream is taken by the server's own running recording instead of this
    /// device's playback (the same rule counts both). Needs the paired server recording another
    /// channel now (`FernsyServer app-order 102 0 20`) and `TEST_RUNNER_FERNSY_SERVER_RECORDING=1`.
    func testRefusedWhileTheStreamIsInUse() throws {
        guard let env = ServerUITests.pairedEnv, ProcessInfo.processInfo.environment["FERNSY_SERVER_RECORDING"] == "1" else {
            throw XCTSkip("no paired Fernsy Server recording another channel in the test environment")
        }
        let app = launch(env.merging(["IPTV_MAXCONN": "1"]) { $1 })
        let show = try running(app)
        Thread.sleep(forTimeInterval: 5)
        longPress(show, app)
        let record = app.buttons["Record on Fernsy Server"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "no Record on Fernsy Server in the menu:\n\(app.debugDescription)")
        record.tap()
        let alert = app.alerts["Fernsy Server"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "no refusal:\n\(app.debugDescription)")
        shot("refused-stream-in-use", app)
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("stream"), "the refusal does not name the stream: \(text)")
        alert.buttons["OK"].tap()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertNotEqual(show.value as? String, "server", "the refused show is marked")
    }

    /// The menu in German, for the user (guide-long-press-record 3.2), with the paired server when
    /// there is one.
    func testMenuInGerman() throws {
        let app = launch(ServerUITests.pairedEnv ?? [:], language: "de")
        let show = try running(app)
        Thread.sleep(forTimeInterval: 5)
        longPress(show, app)
        XCTAssertTrue(app.buttons["Sender ansehen"].waitForExistence(timeout: 10), "no German menu:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Details"].exists, "no Details")
        if ServerUITests.pairedEnv != nil {
            XCTAssertTrue(app.buttons["Auf Fernsy Server aufnehmen"].exists, "the server item is not German")
        }
        Thread.sleep(forTimeInterval: 1)
        shot("menu-de", app)
    }

    /// (c) A later show: Details opens its sheet.
    func testDetailsOfALaterShow() throws {
        let app = launch()
        let later = Int(Date().addingTimeInterval(1800).timeIntervalSince1970)
        let show = try XCTUnwrap(cells(app).first { $0.start > later }?.element, "no later show of channel 101")
        longPress(show, app)
        let details = app.buttons["Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5), "no menu with Details:\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Watch Channel"].exists, "Watch Channel on a later show")
        details.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5), "Details did not open the sheet:\n\(app.debugDescription)")
        shot("details-sheet", app)
    }
}
