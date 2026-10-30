import XCTest

/// Fernsy Cloud on Apple TV (add-recording-cloud 7.2): the fixture recording uploaded with the UI
/// test key is listed under Recordings › Fernsy Cloud, plays from the cloud and seeks. Needs the
/// development server: `TEST_RUNNER_IPTV_CLOUD`, `TEST_RUNNER_IPTV_CLOUDTOKEN`,
/// `TEST_RUNNER_IPTV_CLOUDKEY` and `TEST_RUNNER_FERNSY_CLOUD_FIXTURE_ID` (DEVELOPMENT.md › Fernsy
/// Cloud); skipped without them, as in CI.
final class CloudRecordingsUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    static var cloudEnv: (env: [String: String], fixture: String)? {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPTV_CLOUD"], let token = env["IPTV_CLOUDTOKEN"], let key = env["IPTV_CLOUDKEY"],
              let fixture = env["FERNSY_CLOUD_FIXTURE_ID"] else { return nil }
        return (["IPTV_CLOUD": server, "IPTV_CLOUDTOKEN": token, "IPTV_CLOUDKEY": key], fixture)
    }

    /// "−0:10:23" → 623.
    static func seconds(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "−- ")).split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    func testCloudRecordingPlaysAndSeeks() throws {
        guard let cloud = Self.cloudEnv else { throw XCTSkip("no Fernsy Cloud development server in the test environment") }
        let app = launchDemo(cloud.env)
        showTab("Recordings", app)
        let shelf = app.descendants(matching: .any)["recordings.cloud"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 30), "no Fernsy Cloud shelf:\n\(app.debugDescription)")
        let card = app.buttons["recording.cloud.\(cloud.fixture)"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "the fixture is not listed:\n\(app.debugDescription)")
        shot("cloud-shelf", app)

        // Down into the shelf, then along it to the fixture.
        for _ in 0..<6 where !app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recording.cloud.' AND hasFocus == true")).firstMatch.exists {
            remote.press(.down); Thread.sleep(forTimeInterval: 0.5)
        }
        for _ in 0..<12 where !card.hasFocus {
            remote.press(.right); Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(card.hasFocus, "the fixture card has no focus:\n\(app.debugDescription)")
        remote.press(.select)

        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the cloud recording does not play:\n\(app.debugDescription)")
        let remaining = app.staticTexts["vod.remaining"]
        // The timeline shows after a click; its remaining time tells the position.
        remote.press(.select)
        XCTAssertTrue(remaining.waitForExistence(timeout: 10), "no timeline:\n\(app.debugDescription)")
        let before = try XCTUnwrap(Self.seconds(remaining.label))
        for _ in 0..<9 { remote.press(.right); Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(wait(10) { (Self.seconds(remaining.label) ?? before) <= before - 70 && state.value as? String == "playing" },
                      "seeking 90 s did not land (remaining \(remaining.label), before \(before))")
        shot("cloud-playing", app)
        remote.press(.menu)
    }

    /// Settings › Fernsy Cloud (7.1): with the dev user's active subscription the account shows.
    func testCloudSettingsShowAccount() throws {
        guard let cloud = Self.cloudEnv else { throw XCTSkip("no Fernsy Cloud development server in the test environment") }
        let app = launchDemo(cloud.env)
        showTab("Settings", app)
        let row = app.buttons["settings.cloud"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no Fernsy Cloud row:\n\(app.debugDescription)")
        for _ in 0..<12 where !row.hasFocus {
            remote.press(.down); Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(row.hasFocus, "the Fernsy Cloud row has no focus:\n\(app.debugDescription)")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Subscription"].waitForExistence(timeout: 20), "no account:\n\(app.debugDescription)")
        shot("cloud-settings", app)
    }

    /// Settings › Fernsy Cloud without a subscription (cloud-account-from-icloud-key 4.2): the
    /// offer only when a Mac is known in iCloud (`IPTV_CLOUDMAC`), otherwise the note; never a sign-in.
    func testOfferOnlyWithAMac() throws {
        guard let cloud = Self.cloudEnv else { throw XCTSkip("no Fernsy Cloud development server in the test environment") }
        for mac in ["0", "1"] {
            // No dev token: no subscription and no key, as on a fresh Apple TV.
            let app = launchDemo(["IPTV_CLOUD": cloud.env["IPTV_CLOUD"]!, "IPTV_CLOUDKEY": "local", "IPTV_CLOUDMAC": mac])
            showTab("Settings", app)
            let row = app.buttons["settings.cloud"]
            XCTAssertTrue(row.waitForExistence(timeout: 30), "no Fernsy Cloud row:\n\(app.debugDescription)")
            for _ in 0..<12 where !row.hasFocus {
                remote.press(.down); Thread.sleep(forTimeInterval: 0.4)
            }
            remote.press(.select)
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
