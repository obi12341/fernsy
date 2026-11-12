import XCTest

/// Fernsy Server on Apple TV (headless-recorder 4.2, 4.3): with the control key of a paired
/// server, Recordings shows the server's orders, Settings › Fernsy Cloud › Fernsy Server its
/// state, and a show's record dialog orders it on the server. Needs a paired server against the dev services (DEVELOPMENT.md › Fernsy Server) and
/// `TEST_RUNNER_IPTV_CONTROL`, `TEST_RUNNER_IPTV_CONTROLKEY` (base64 key JSON of that space),
/// `TEST_RUNNER_IPTV_CLOUD`, `TEST_RUNNER_IPTV_CLOUDTOKEN`; skipped without them, as in CI.
final class ServerUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    static var serverEnv: [String: String]? {
        let env = ProcessInfo.processInfo.environment
        guard let control = env["IPTV_CONTROL"], let key = env["IPTV_CONTROLKEY"], let cloud = env["IPTV_CLOUD"],
              let token = env["IPTV_CLOUDTOKEN"] else { return nil }
        return ["IPTV_CONTROL": control, "IPTV_CONTROLKEY": key, "IPTV_CLOUD": cloud, "IPTV_CLOUDTOKEN": token, "IPTV_CLOUDKEY": "local"]
    }

    private func select(_ id: String, _ app: XCUIApplication) {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: 20), "no \(id):\n\(app.debugDescription)")
        for _ in 0..<12 where !element.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(element.hasFocus, "\(id) has no focus:\n\(app.debugDescription)")
        remote.press(.select)
    }

    func testServerOrdersAndSettings() throws {
        guard let env = Self.serverEnv else { throw XCTSkip("no paired Fernsy Server and dev services in the test environment") }
        let app = launchDemo(env)
        showTab("Recordings", app)
        let shelf = app.descendants(matching: .any)["recordings.server"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 30), "no Fernsy Server shelf:\n\(app.debugDescription)")
        shot("server-shelf", app)

        showTab("Settings", app)
        select("settings.cloud", app)
        select("cloud.server", app)
        XCTAssertTrue(app.descendants(matching: .any)["server.connection"].waitForExistence(timeout: 30), "not shown as paired:\n\(app.debugDescription)")
        shot("server-settings", app)
    }

    /// Right after launch, before Recordings or Settings were opened, a later show's record dialog
    /// offers the server, orders the show and takes it back: the app reads the server's state at
    /// launch (up to 2.4.1 it did not, and the dialog had no server button until then).
    func testRecordDialogOffersTheServerRightAfterLaunch() throws {
        guard let env = Self.serverEnv else { throw XCTSkip("no paired Fernsy Server and dev services in the test environment") }
        let app = launchDemo(env)
        focusLaterShow(app)
        let cell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
        let id = cell.identifier
        choose("Record on Fernsy Server", app, shot: "server-dialog")
        XCTAssertTrue(waitForLog("Fernsy Server: scheduled"), "the order was not written")
        // The guide marks the show while the server has its order.
        XCTAssertTrue(wait(10) { app.buttons[id].value as? String == "server" }, "\(id) is not marked as on the server")
        shot("server-guide-mark", app)
        choose("Remove from Server", app, shot: "server-dialog-ordered")
        XCTAssertTrue(wait(10) { app.buttons[id].value as? String != "server" }, "\(id) is still marked")
        remote.press(.select)
        XCTAssertTrue(app.sheets.buttons["Record on Fernsy Server"].firstMatch.waitForExistence(timeout: 10),
                      "the order was not taken back:\n\(app.debugDescription)")
        remote.press(.menu)
    }

    /// Ordering while the server is away says that it records once it is back. Needs the paired
    /// server stopped for more than ten minutes and `TEST_RUNNER_FERNSY_SERVER_AWAY=1` beside the
    /// variables above; skipped otherwise.
    func testOrderingWhileTheServerIsAwaySaysSo() throws {
        guard let env = Self.serverEnv, ProcessInfo.processInfo.environment["FERNSY_SERVER_AWAY"] != nil else {
            throw XCTSkip("no paired Fernsy Server that has been away for ten minutes in the test environment")
        }
        let app = launchDemo(env)
        focusLaterShow(app)
        choose("Record on Fernsy Server", app, shot: "server-dialog-away")
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'has not reported for a while'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15), "no note that the server is away:\n\(app.debugDescription)")
        shot("server-away", app)
        remote.press(.select)
        XCTAssertTrue(wait(5) { !note.exists }, "the note stayed open")
        Thread.sleep(forTimeInterval: 1)
        choose("Remove from Server", app, shot: "server-dialog-away-ordered")
    }

    /// The guide with focus on a show that starts later.
    private func focusLaterShow(_ app: XCUIApplication) {
        showLiveView("live.view.guide", app)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide cells:\n\(app.debugDescription)")
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
        for direction in [XCUIRemote.Button.down, .right, .right] where !focused.exists {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "no show has focus:\n\(app.debugDescription)")
        // Right until the focused show starts in the future.
        for _ in 0..<8 {
            let start = Double(focused.identifier.split(separator: ".").last ?? "") ?? 0
            if start > Date().timeIntervalSince1970 { break }
            remote.press(.right); Thread.sleep(forTimeInterval: 0.6)
        }
    }

    /// Clicks the focused show and picks `title` in its dialog (the buttons are in a column).
    private func choose(_ title: String, _ app: XCUIApplication, shot name: String) {
        remote.press(.select)
        let button = app.sheets.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no “\(title)” in the dialog:\n\(app.debugDescription)")
        for _ in 0..<4 where !button.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(button.hasFocus, "“\(title)” has no focus:\n\(app.debugDescription)")
        shot(name, app)
        remote.press(.select)
        XCTAssertTrue(wait(5) { !button.exists }, "the dialog stayed open")
        // Kept: the dialog closes with an animation, and a click during it is lost.
        Thread.sleep(forTimeInterval: 1)
    }
}
