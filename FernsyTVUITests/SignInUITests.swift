import XCTest

/// First launch without an account (tvos-live 2.2): welcome screen, the IPTV form keeps its
/// values after a rejected sign-in, and "Try the Demo" signs in to the demo server.
final class SignInUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testWrongPasswordKeepsTheFormAndTheDemoSignsIn() throws {
        let app = XCUIApplication()
        // No account: an empty IPTV_SERVER and no keychain.
        app.launchEnvironment = ["FERNSY_NO_KEYCHAIN": "1", "IPTV_SERVER": ""]
        app.launch()
        let remote = XCUIRemote.shared

        let card = app.buttons["welcome.iptv"]
        XCTAssertTrue(card.waitForExistence(timeout: 15), "no welcome screen:\n\(app.debugDescription)")
        remote.press(.select)

        let server = app.buttons["signin.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10), "the IPTV form did not open")
        enter("https://fernsy-demo.mobilistics.workers.dev", into: server, app: app)
        move(.down, to: app.buttons["signin.username"], app: app)
        enter("demo", into: app.buttons["signin.username"], app: app)
        move(.down, to: app.buttons["signin.password"], app: app)
        enter("wrong", into: app.buttons["signin.password"], app: app)
        move(.down, to: app.buttons["signin.submit"], app: app)
        remote.press(.select)

        let error = app.staticTexts["signin.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 20), "no error after a wrong password")
        XCTAssertEqual(app.buttons["signin.username"].value as? String, "demo", "the username was not kept")

        move(.right, to: app.buttons["signin.demo"], app: app)
        remote.press(.select)
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Live TV"].waitForExistence(timeout: 30), "the demo account did not sign in")
    }

    /// Selects the focused field, types into tvOS' keyboard and returns to the form.
    private func enter(_ text: String, into field: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(field), "\(field.identifier) has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        app.typeText(text)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(field), "back from the keyboard, \(field.identifier) has no focus")
        let shown = field.identifier.hasSuffix("password") ? String(repeating: "•", count: text.count) : text
        XCTAssertEqual(field.value as? String, shown, "\(field.identifier) does not show what was typed:\n\(app.debugDescription)")
    }

    /// Presses `direction` until `element` has focus (the focus engine may still be settling).
    private func move(_ direction: XCUIRemote.Button, to element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<3 {
            XCUIRemote.shared.press(direction)
            if waitForFocus(element, timeout: 2) { return }
        }
        XCTFail("\(element.identifier) did not get focus:\n\(app.debugDescription)")
    }

}
