import XCTest

/// Fernsy Cloud on iPhone and iPad (add-recording-cloud 6.2): the Recordings tab lists the
/// fixture uploaded with the UI test key, it plays from the cloud and seeks. Needs the development
/// server (`TEST_RUNNER_IPTV_CLOUD`, `TEST_RUNNER_IPTV_CLOUDTOKEN`, `TEST_RUNNER_IPTV_CLOUDKEY`,
/// `TEST_RUNNER_FERNSY_CLOUD_FIXTURE_ID`, DEVELOPMENT.md › Fernsy Cloud); skipped without it.
final class CloudRecordingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    static var cloudEnv: (env: [String: String], fixture: String)? {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPTV_CLOUD"], let token = env["IPTV_CLOUDTOKEN"], let key = env["IPTV_CLOUDKEY"],
              let fixture = env["FERNSY_CLOUD_FIXTURE_ID"] else { return nil }
        return (["IPTV_CLOUD": server, "IPTV_CLOUDTOKEN": token, "IPTV_CLOUDKEY": key], fixture)
    }

    static func seconds(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "−- ")).split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
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

    func testCloudRecordingPlaysAndSeeks() throws {
        guard let cloud = Self.cloudEnv else { throw XCTSkip("no Fernsy Cloud development server in the test environment") }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
            "IPTV_TAB": "recordings",
        ].merging(cloud.env) { $1 }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        let row = app.buttons["cloud.recording.\(cloud.fixture)"]
        XCTAssertTrue(row.waitForExistence(timeout: 40), "the fixture is not listed:\n\(app.debugDescription)")
        shot("cloud-recordings", app)
        row.tap()

        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.exists && state.value as? String == "playing" }, "the cloud recording does not play:\n\(app.debugDescription)")
        if UIDevice.current.userInterfaceIdiom == .phone, XCUIDevice.shared.orientation != .landscapeLeft {
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 1)
        }
        let forward = app.buttons["player.forward10"]
        if !forward.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        XCTAssertTrue(forward.waitForExistence(timeout: 5), "no controls:\n\(app.debugDescription)")
        let remaining = app.staticTexts["vod.remaining"]
        let before = try XCTUnwrap(Self.seconds(remaining.label))
        for _ in 0..<9 {
            if !forward.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            forward.tap()
        }
        XCTAssertTrue(wait(10) { (Self.seconds(remaining.label) ?? before) <= before - 70 && state.value as? String == "playing" },
                      "seeking 90 s did not land (remaining \(remaining.label), before \(before))")
        shot("cloud-playing", app)
    }

    /// Settings › Fernsy Cloud (6.1): with the dev user's active subscription the account shows.
    func testCloudSettingsShowAccount() throws {
        guard let cloud = Self.cloudEnv else { throw XCTSkip("no Fernsy Cloud development server in the test environment") }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_TAB": "settings",
        ].merging(cloud.env) { $1 }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let row = app.buttons["settings.cloud"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no Fernsy Cloud row:\n\(app.debugDescription)")
        row.tap()
        XCTAssertTrue(app.staticTexts["Subscription"].waitForExistence(timeout: 20), "no account:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Storage"].exists)
        shot("cloud-settings", app)
    }

    /// Settings › Fernsy Cloud without a subscription (cloud-account-from-icloud-key 4.1): the
    /// offer only when a Mac is known in iCloud (`IPTV_CLOUDMAC`), otherwise the note; never a sign-in.
    func testOfferOnlyWithAMac() throws {
        guard let cloud = Self.cloudEnv else { throw XCTSkip("no Fernsy Cloud development server in the test environment") }
        for mac in ["0", "1"] {
            let app = XCUIApplication()
            // No dev token: no subscription and no key, as on a fresh device.
            app.launchEnvironment = [
                "FERNSY_NO_KEYCHAIN": "1",
                "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
                "IPTV_USER": "demo",
                "IPTV_PASS": "demo",
                "IPTV_TAB": "settings",
                "IPTV_CLOUD": cloud.env["IPTV_CLOUD"]!,
                "IPTV_CLOUDKEY": "local",
                "IPTV_CLOUDMAC": mac,
            ]
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            let row = app.buttons["settings.cloud"]
            XCTAssertTrue(row.waitForExistence(timeout: 30), "no Fernsy Cloud row:\n\(app.debugDescription)")
            row.tap()
            if mac == "0" {
                XCTAssertTrue(app.staticTexts["cloud.needsMac"].waitForExistence(timeout: 20), "no Mac note:\n\(app.debugDescription)")
                XCTAssertFalse(app.buttons["cloud.subscribe"].exists)
                shot("cloud-needs-mac", app)
            } else {
                XCTAssertTrue(app.buttons["cloud.subscribe"].waitForExistence(timeout: 20), "no offer:\n\(app.debugDescription)")
                XCTAssertFalse(app.staticTexts["cloud.needsMac"].exists)
                shot("cloud-offer", app)
            }
            XCTAssertFalse(app.buttons["cloud.signIn"].exists)
            app.terminate()
        }
    }
}
