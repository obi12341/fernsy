import XCTest

/// Fernsy Server on Apple TV (headless-recorder 4.2, 4.3): with the control key of a paired
/// server, Recordings shows the server's orders and Settings › Fernsy Cloud › Fernsy Server its
/// state. Needs a paired server against the dev services (DEVELOPMENT.md › Fernsy Server) and
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
}
