import XCTest

/// The assistant's sheet on iPhone and iPad (cloud-assistant 3.4, 5.3) with the stand-in relay
/// (`IPTV_ASSISTANT_STUB`, no model calls): opened from Start, the consent before the first
/// request, an answer in the conversation, a request that plays its channel, Done closes it.
final class AssistantUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Fernsy Cloud on (an unreachable server: nothing leaves the simulator), the stand-in relay.
    private func launch(consent: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
            "IPTV_TAB": "start",
            "IPTV_CLOUD": "http://127.0.0.1:9",
            "IPTV_CLOUDKEY": "local",
            "IPTV_ASSISTANT_STUB": "1",
            "IPTV_ASSISTANT_CONSENT": consent,
        ]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Opens the assistant from Start's toolbar.
    private func open(_ app: XCUIApplication) {
        let button = app.buttons["assistant.open"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no assistant button on Start:\n\(app.debugDescription)")
        button.tap()
    }

    func testConsentThenAnswerThenDone() {
        let app = launch(consent: "0")
        open(app)
        let agree = app.buttons["assistant.consent.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 10), "no consent before the first request:\n\(app.debugDescription)")
        XCTAssertFalse(app.textFields["assistant.field"].exists, "the text field shows before consent")
        shot("assistant-consent", app)
        agree.tap()

        let field = app.textFields["assistant.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no text field after consent:\n\(app.debugDescription)")
        field.tap()
        field.typeText("Write me a poem\n")
        let answer = app.staticTexts.matching(identifier: "assistant.answer").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 15), "no answer:\n\(app.debugDescription)")
        XCTAssertTrue(answer.label.contains("Fernsy"), "unexpected answer \(answer.label)")
        XCTAssertTrue(app.staticTexts.matching(identifier: "assistant.request").firstMatch.exists, "the request is not in the conversation")
        shot("assistant-answer", app)

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Done did not close the assistant")
    }

    func testRequestPlaysItsChannel() {
        let app = launch(consent: "1")
        open(app)
        let field = app.textFields["assistant.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no assistant sheet:\n\(app.debugDescription)")
        field.tap()
        field.typeText("spiel ZDF\n")
        // The sheet closes for the player.
        let state = app.descendants(matching: .any)["player.state"]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, state.value as? String != "playing" { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(state.value as? String, "playing", "the channel does not play:\n\(app.debugDescription)")
        XCTAssertFalse(field.exists, "the sheet stayed over the player")
    }
}
