import XCTest

/// Jellyfin sign-in (tvos-library 2.2): from the welcome screen (a wrong password keeps the form
/// with the message, then the right one shows the Jellyfin tab) and from Settings › Add Account.
/// Needs the local test Jellyfin on 127.0.0.1:8097 (scripts/jellyfin-test-server.sh).
final class JellyfinSignInUITests: FernsyUITestCase {
    func testFromTheWelcomeScreen() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = XCUIApplication()
        app.launchEnvironment = ["FERNSY_NO_KEYCHAIN": "1", "IPTV_SERVER": ""]
        app.launch()
        let card = app.buttons["welcome.jellyfin"]
        XCTAssertTrue(card.waitForExistence(timeout: 15), "no Jellyfin card")
        move(.right, to: card, app)
        XCUIRemote.shared.press(.select)
        fill(app, password: "wrong")
        XCTAssertTrue(app.staticTexts["jfsignin.error"].waitForExistence(timeout: 20), "no error after a wrong password")
        XCTAssertEqual(app.textFields["jfsignin.username"].value as? String, "fixture", "the username was not kept")
        // The right password: clear and type it again.
        move(.up, to: app.secureTextFields["jfsignin.password"], app)
        XCUIRemote.shared.press(.select)
        for _ in 0..<8 { app.typeText(XCUIKeyboardKey.delete.rawValue) }
        app.typeText("fixture-pass")
        XCUIRemote.shared.press(.menu)
        move(.down, to: app.buttons["jfsignin.submit"], app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Jellyfin"].waitForExistence(timeout: 20), "no Jellyfin tab after signing in")
    }

    func testFromSettings() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = launchDemo()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        let gear = app.tabBars.firstMatch.buttons["Settings"]
        for _ in 0..<12 where !gear.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(gear.hasFocus, "the gear has no focus")
        let add = app.buttons["settings.addAccount"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        for _ in 0..<4 where !add.hasFocus { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCUIRemote.shared.press(.select)
        let jellyfin = app.buttons["add.jellyfin"]
        XCTAssertTrue(jellyfin.waitForExistence(timeout: 5), "Add Account offers no Jellyfin server")
        for _ in 0..<4 where !jellyfin.hasFocus { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCUIRemote.shared.press(.select)
        fill(app, password: "fixture-pass")
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Jellyfin"].waitForExistence(timeout: 20), "no Jellyfin tab after signing in from Settings")
    }

    /// Server, user and the given password, then Sign In.
    private func fill(_ app: XCUIApplication, password: String) {
        let server = app.textFields["jfsignin.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10), "no Jellyfin form")
        XCTAssertTrue(wait(5) { server.hasFocus }, "the server field has no focus")
        enter("http://127.0.0.1:8097", app)
        move(.down, to: app.textFields["jfsignin.username"], app)
        enter("fixture", app)
        move(.down, to: app.secureTextFields["jfsignin.password"], app)
        enter(password, app)
        move(.down, to: app.buttons["jfsignin.submit"], app)
        XCUIRemote.shared.press(.select)
    }

    private func enter(_ text: String, _ app: XCUIApplication) {
        XCUIRemote.shared.press(.select)
        app.typeText(text)
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func move(_ direction: XCUIRemote.Button, to element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<3 {
            XCUIRemote.shared.press(direction)
            if wait(2, { element.exists && element.hasFocus }) { return }
        }
        XCTFail("\(element.identifier) did not get focus:\n\(app.debugDescription)")
    }
}
