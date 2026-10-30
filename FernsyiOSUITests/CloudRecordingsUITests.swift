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

    // MARK: Downloads and opening offline (offline-recording-downloads 3.1, 3.2, 4.1–4.3)

    private func launch(_ env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["FERNSY_NO_KEYCHAIN": "1", "IPTV_MCP": "1", "IPTV_MCPTOKEN": "test"].merging(env) { $1 }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    private static let demo = ["IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev", "IPTV_USER": "demo", "IPTV_PASS": "demo"]

    /// A tool of the app's debug MCP server (port 52326).
    private func mcp(_ tool: String, _ arguments: String = "{}") -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:52326/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        var text = "no answer"
        URLSession.shared.dataTask(with: request) { data, _, _ in
            text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no data"
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        return text
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func playAndSeek(_ app: XCUIApplication, _ row: XCUIElement) throws {
        row.tap()
        let state = element(app, "player.state")
        XCTAssertTrue(wait(30) { state.exists && state.value as? String == "playing" }, "the download does not play:\n\(app.debugDescription)")
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
    }

    func testDownloadPlaysOffline() throws {
        guard let cloud = Self.cloudEnv else { throw XCTSkip("no Fernsy Cloud development server in the test environment") }
        let id = cloud.fixture

        // 1. Online: download the fixture through the background session.
        var app = launch(Self.demo.merging(cloud.env) { $1 }.merging(["IPTV_TAB": "recordings"]) { $1 })
        let row = app.buttons["cloud.recording.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 40), "the fixture is not listed:\n\(app.debugDescription)")
        if element(app, "cloud.downloaded.\(id)").waitForExistence(timeout: 2) {
            // Left from an earlier run.
            row.press(forDuration: 1.0)
            app.buttons["Remove Download"].firstMatch.tap()
        }
        let download = app.buttons["cloud.download.\(id)"]
        XCTAssertTrue(download.waitForExistence(timeout: 10), "no Download button:\n\(app.debugDescription)")
        download.tap()
        XCTAssertTrue(element(app, "cloud.downloaded.\(id)").waitForExistence(timeout: 240), "not downloaded:\n\(app.debugDescription)")
        shot("download-done", app)
        app.terminate()

        // 2. No network, empty Caches: the tabs open, Recordings lists the download, it plays and seeks.
        app = launch(Self.demo.merging(cloud.env) { $1 }.merging(["IPTV_TESTOFFLINE": "1", "IPTV_FRESHCATALOG": "1", "IPTV_TAB": "recordings"]) { $1 })
        XCTAssertTrue(element(app, "tabs").waitForExistence(timeout: 20), "no tabs offline:\n\(app.debugDescription)")
        XCTAssertTrue(element(app, "offline.note").exists, "no offline note")
        XCTAssertTrue(element(app, "cloud.offline").waitForExistence(timeout: 10), "no offline line in Recordings")
        let offlineRow = app.buttons["cloud.recording.\(id)"]
        XCTAssertTrue(offlineRow.waitForExistence(timeout: 10), "the download is not listed offline:\n\(app.debugDescription)")
        shot("offline-recordings", app)
        try playAndSeek(app, offlineRow)
        shot("offline-playing", app)
        app.terminate()

        // 3. The network returns: the channel list loads by itself.
        app = launch(Self.demo.merging(cloud.env) { $1 }.merging(["IPTV_TESTOFFLINE": "1", "IPTV_FRESHCATALOG": "1"]) { $1 })
        XCTAssertTrue(element(app, "offline.note").waitForExistence(timeout: 20), "not offline")
        _ = mcp("set_offline", #"{"on":false}"#)
        XCTAssertTrue(wait(30) { self.mcp("get_log", #"{"query":"signed in"}"#).contains("signed in, ") }, "no sign-in after the network returned")
        XCTAssertTrue(wait(10) { !self.element(app, "offline.note").exists }, "the offline note stays")
        app.terminate()

        // 4. Only a stored Jellyfin session (JF_CACHEONLY, no server), offline: tabs and the download.
        app = launch(cloud.env.merging(["JF_CACHEONLY": "https://jellyfin.invalid|server|user", "IPTV_TESTOFFLINE": "1", "IPTV_TAB": "recordings"]) { $1 })
        XCTAssertTrue(element(app, "tabs").waitForExistence(timeout: 20), "no tabs with Jellyfin only:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["cloud.recording.\(id)"].waitForExistence(timeout: 10), "no download with Jellyfin only")
        app.terminate()

        // 5. Online: Settings shows the space, "Remove Download" brings back "Download".
        app = launch(Self.demo.merging(cloud.env) { $1 }.merging(["IPTV_TAB": "settings"]) { $1 })
        let settingsRow = app.buttons["settings.cloud"]
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 30))
        settingsRow.tap()
        XCTAssertTrue(element(app, "cloud.downloadsStorage").waitForExistence(timeout: 20), "no downloads storage:\n\(app.debugDescription)")
        shot("downloads-storage", app)
        app.terminate()
        app = launch(Self.demo.merging(cloud.env) { $1 }.merging(["IPTV_TAB": "recordings"]) { $1 })
        let onlineRow = app.buttons["cloud.recording.\(id)"]
        XCTAssertTrue(onlineRow.waitForExistence(timeout: 40))
        onlineRow.press(forDuration: 1.0)
        app.buttons["Remove Download"].firstMatch.tap()
        XCTAssertTrue(app.buttons["cloud.download.\(id)"].waitForExistence(timeout: 10), "Download does not come back")
    }

    /// A rejected password is no connection problem: the welcome screen shows as before, not the
    /// offline tabs.
    func testWrongPasswordIsNotOffline() throws {
        let app = launch(["IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev", "IPTV_USER": "demo", "IPTV_PASS": "wrong", "IPTV_FRESHCATALOG": "1"])
        XCTAssertTrue(app.buttons["welcome.iptv"].waitForExistence(timeout: 30), "no welcome screen:\n\(app.debugDescription)")
        XCTAssertTrue(wait(5) { self.mcp("get_log", #"{"query":"sign-in or catalog failed"}"#).contains("failed") }, "not refused by the server")
        XCTAssertFalse(element(app, "tabs").exists)
        XCTAssertFalse(element(app, "offline.note").exists)
    }

    /// A download that finishes while the app is in the background (3.2): the system hands the
    /// session's events to the app, and the recording is downloaded when it opens again.
    func testDownloadFinishesInTheBackground() throws {
        guard let cloud = Self.cloudEnv else { throw XCTSkip("no Fernsy Cloud development server in the test environment") }
        let id = cloud.fixture
        let app = launch(Self.demo.merging(cloud.env) { $1 }.merging(["IPTV_TAB": "recordings"]) { $1 })
        let row = app.buttons["cloud.recording.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 40))
        if element(app, "cloud.downloaded.\(id)").waitForExistence(timeout: 2) {
            row.press(forDuration: 1.0)
            app.buttons["Remove Download"].firstMatch.tap()
        }
        let download = app.buttons["cloud.download.\(id)"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.tap()
        XCTAssertTrue(element(app, "cloud.downloading.\(id)").waitForExistence(timeout: 20), "the download does not start")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 90)
        app.activate()
        XCTAssertTrue(element(app, "cloud.downloaded.\(id)").waitForExistence(timeout: 60), "not downloaded after the background:\n\(app.debugDescription)")
        let log = mcp("get_log", #"{"query":"Fernsy Cloud"}"#)
        print("BACKGROUND LOG: \(log.prefix(3000))")
        row.press(forDuration: 1.0)
        app.buttons["Remove Download"].firstMatch.tap()
    }
}

