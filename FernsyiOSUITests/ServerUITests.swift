import XCTest

/// Fernsy Server from the iPhone (headless-recorder 4.2, 4.3, 6.2): pairs with a running server
/// using the code from its status page, then schedules a show from the guide and sees the
/// server's state. Needs a server started against the dev services (DEVELOPMENT.md › Fernsy
/// Server) and `TEST_RUNNER_FERNSY_SERVER_STATUS` (its `/status.json`), `TEST_RUNNER_IPTV_CONTROL`,
/// `TEST_RUNNER_IPTV_CLOUD`, `TEST_RUNNER_IPTV_CLOUDTOKEN`; skipped without them.
final class ServerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    static var serverEnv: (env: [String: String], status: URL)? {
        let env = ProcessInfo.processInfo.environment
        guard let status = env["FERNSY_SERVER_STATUS"].flatMap(URL.init(string:)), let control = env["IPTV_CONTROL"],
              let cloud = env["IPTV_CLOUD"], let token = env["IPTV_CLOUDTOKEN"] else { return nil }
        // A fresh control key per run, in memory: the test pairs a new space every time. Given keys
        // (`IPTV_CONTROLKEY`, `IPTV_CLOUDKEY`, base64 key JSON) let an end-to-end run go on
        // with the same space and cloud key from the command line and on the Apple TV.
        let raw = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = env["IPTV_CONTROLKEY"] ?? Data(#"{"raw":"\#(raw.base64EncodedString())"}"#.utf8).base64EncodedString()
        return (["IPTV_CONTROL": control, "IPTV_CLOUD": cloud, "IPTV_CLOUDTOKEN": token, "IPTV_CLOUDKEY": env["IPTV_CLOUDKEY"] ?? "local",
                 "IPTV_CONTROLKEY": key], status)
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func XTCAssertLabel(_ element: XCUIElement, contains text: String, _ app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "no \(element):\n\(app.debugDescription)")
        XCTAssertTrue(element.label.contains(text) || (element.value as? String ?? "").contains(text),
                      "\(element.label) does not name \(text)")
    }

    /// The code the server shows now, from its status page.
    private func pairingCode(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["pairingCode"] as? String, "the server is paired already; restart it with an empty data folder")
    }

    func testPairAndScheduleFromTheGuide() throws {
        guard let server = Self.serverEnv else { throw XCTSkip("no Fernsy Server and dev services in the test environment") }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_LIVEVIEW": "guide",
        ].merging(server.env) { $1 }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        // Settings (a button on Start on the iPhone) › Fernsy Cloud › Fernsy Server.
        let settings = app.buttons["start.settings"]
        if settings.waitForExistence(timeout: 20) { settings.tap() }
        let cloud = app.buttons["settings.cloud"]
        XCTAssertTrue(cloud.waitForExistence(timeout: 20), "no Fernsy Cloud in Settings:\n\(app.debugDescription)")
        cloud.tap()
        let serverLink = app.buttons["cloud.server"]
        XCTAssertTrue(serverLink.waitForExistence(timeout: 20), "no Fernsy Server row:\n\(app.debugDescription)")
        serverLink.tap()
        let field = app.textFields["server.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(try pairingCode(server.status).lowercased())
        app.buttons["server.pair"].tap()
        let connection = app.descendants(matching: .any)["server.connection"]
        XCTAssertTrue(connection.waitForExistence(timeout: 90), "not paired:\n\(app.debugDescription)")
        shot("server-paired", app)

        // The login the server records with, and sending this device's login (server-login-update).
        let login = app.descendants(matching: .any)["server.login"]
        XTCAssertLabel(login, contains: "demo @", app)
        let useLogin = app.buttons["server.useLogin"]
        XCTAssertTrue(useLogin.waitForExistence(timeout: 10), "no Use This Login:\n\(app.debugDescription)")
        useLogin.tap()
        // The server checks it within its poll interval; demo/demo is accepted, so no note stays.
        let note = app.descendants(matching: .any)["server.loginNote"]
        let settled = NSPredicate(format: "exists == false")
        expectation(for: settled, evaluatedWith: note)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(useLogin.isEnabled)
        shot("server-login", app)

        // The guide: a show of channel 101 that starts later.
        app.tabBars.buttons["Live TV"].tap()
        let later = Int(Date().addingTimeInterval(600).timeIntervalSince1970)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.101.' AND NOT (identifier CONTAINS '.gap.')"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 30), "no listings in the guide:\n\(app.debugDescription)")
        let future = cells.allElementsBoundByIndex.first { cell in
            Int(cell.identifier.split(separator: ".").last ?? "") ?? 0 > later
        }
        let show = try XCTUnwrap(future, "no later show of channel 101")
        // The next show may start just past the right edge: scroll the guide along its row.
        let window = app.windows.firstMatch
        for _ in 0..<4 where !window.frame.contains(CGPoint(x: show.frame.minX + 30, y: show.frame.midY)) {
            let y = show.frame.midY / window.frame.height
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: y)))
        }
        show.tap()
        let record = app.buttons["server.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "no Record on Fernsy Server:\n\(app.debugDescription)")
        record.tap()
        let state = app.descendants(matching: .any)["server.orderState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        // The server answers within its poll interval.
        let scheduled = NSPredicate(format: "label CONTAINS 'Scheduled on the server'")
        expectation(for: scheduled, evaluatedWith: state)
        waitForExpectations(timeout: 90)
        shot("server-scheduled", app)

        // Cancelling removes the order.
        app.buttons["Cancel Recording"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 20), "the order stayed:\n\(app.debugDescription)")
    }
}
