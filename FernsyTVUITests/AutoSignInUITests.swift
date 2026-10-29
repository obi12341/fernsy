import XCTest

/// Sign-in with the logins in iCloud at launch (icloud-auto-signin 3.1, 3.2): without an account
/// the app signs in with them and never shows the welcome screen; a rejected login shows the
/// welcome screen with the reason and the offer; signing out offers the login instead of using it.
final class AutoSignInUITests: FernsyUITestCase {
    /// No account on this Apple TV (no keychain, no IPTV_SERVER), `login` as if found in iCloud.
    private func launch(iCloud login: String, delay: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["FERNSY_NO_KEYCHAIN": "1", "IPTV_SERVER": "", "IPTV_TESTICLOUDLOGIN": login, "IPTV_TESTICLOUDDELAY": "\(delay)",
                                 "IPTV_MCP": "1", "IPTV_MCPTOKEN": "test"]
        app.launch()
        return app
    }

    /// Waits for the tab bar, failing as soon as the welcome screen shows.
    private func signsInWithoutWelcome(_ tab: String, _ app: XCUIApplication) {
        let welcome = app.buttons["welcome.iptv"]
        let target = app.tabBars.firstMatch.buttons[tab]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline && !target.exists {
            XCTAssertFalse(welcome.exists, "the welcome screen showed:\n\(app.debugDescription)")
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(target.exists, "no \(tab) tab after launch:\n\(app.debugDescription)")
        XCTAssertFalse(welcome.exists, "the welcome screen showed")
    }

    func testProviderLoginSignsInAtLaunch() {
        // iCloud answers after 3 s, as on a device; app.launch() returns only once the app idles.
        let app = launch(iCloud: "demo", delay: 3)
        // The launch screen with its steps, checked off in turn, at least 1.5 s.
        let screen = app.descendants(matching: .any)["icloud.signingIn"]
        XCTAssertTrue(screen.waitForExistence(timeout: 10), "no launch screen:\n\(app.debugDescription)")
        XCTAssertEqual(app.descendants(matching: .any)["icloud.step.found"].value as? String, "running", "no running iCloud step")
        shot("auto-signin-looking", app)
        let channels = app.descendants(matching: .any)["icloud.step.channels"]
        // On a slow CI runner one look at the screen takes seconds and can miss the moment all
        // steps are checked off before the screen fades; then the signed-in app below is the proof.
        XCTAssertTrue(wait(20) { !screen.exists || channels.exists && channels.value as? String == "done" },
                      "the channels step is not checked off:\n\(app.debugDescription)")
        if screen.exists {
            for step in ["found", "provider"] {
                XCTAssertEqual(app.descendants(matching: .any)["icloud.step.\(step)"].value as? String, "done", "\(step) is not checked off")
            }
            // At once: shot() waits a second, and the screen fades soon after the last checkmark.
            let steps = XCTAttachment(screenshot: app.screenshot())
            steps.name = "auto-signin-steps"
            steps.lifetime = .keepAlways
            add(steps)
        }
        signsInWithoutWelcome("Live TV", app)
        shot("auto-signin-start", app)
    }

    func testRejectedLoginShowsTheWelcomeScreen() {
        let app = launch(iCloud: "demo-wrong")
        XCTAssertTrue(app.buttons["welcome.iptv"].waitForExistence(timeout: 30), "no welcome screen after a rejected login")
        XCTAssertTrue(app.buttons["welcome.synced.iptv"].exists, "the login is not offered")
        XCTAssertTrue(app.staticTexts["welcome.synced.error"].exists, "no reason:\n\(app.debugDescription)")
        shot("auto-signin-rejected", app)
    }

    func testSigningOutOffersTheLogin() {
        let app = launch(iCloud: "demo")
        signsInWithoutWelcome("Live TV", app)
        showTab("Settings", app)
        let remote = XCUIRemote.shared
        let account = app.buttons["settings.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        for _ in 0..<8 where !account.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        remote.press(.select)
        let signOut = app.buttons["settings.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        for _ in 0..<12 where !signOut.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        remote.press(.select)
        // The confirmation's own "Sign Out", not the row behind it.
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Sign Out' AND identifier != 'settings.signOut'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation:\n\(app.debugDescription)")
        shot("signout-dialog", app)
        for _ in 0..<4 where !confirm.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        remote.press(.select)
        shot("signout-after", app)
        XCTAssertTrue(app.buttons["welcome.iptv"].waitForExistence(timeout: 15), "no welcome screen after signing out")
        XCTAssertTrue(app.buttons["welcome.synced.iptv"].waitForExistence(timeout: 10), "the iCloud login is not offered")
        // Kept: real time, it checks that the app does not sign in again by itself.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "signed in again by itself")
    }

    func testJellyfinLoginSignsInAtLaunch() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = launch(iCloud: "jellyfin")
        signsInWithoutWelcome("Jellyfin", app)
    }
}
