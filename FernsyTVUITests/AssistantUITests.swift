import XCTest

/// The assistant's overlay (cloud-assistant 3.5, 5.3) with the stand-in relay
/// (`IPTV_ASSISTANT_STUB`, no model calls): opened from Start with focus in the text field, a
/// request plays its channel and the answer shows over the player, Back closes it; before the
/// first request the consent shows.
final class AssistantUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    /// Fernsy Cloud on (an unreachable server: nothing leaves the simulator), the stand-in relay.
    private func launch(consent: String) -> XCUIApplication {
        launchDemo(["IPTV_CLOUD": "http://127.0.0.1:9", "IPTV_CLOUDKEY": "local",
                    "IPTV_ASSISTANT_STUB": "1", "IPTV_ASSISTANT_CONSENT": consent],
                   arguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
    }

    /// Start's "Ask Fernsy" with focus, then selected.
    private func openFromStart(_ app: XCUIApplication) {
        let open = app.buttons["assistant.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "no assistant button on Start:\n\(app.debugDescription)")
        for _ in 0..<4 where !open.hasFocus { pressAndWaitForFocusMove(.down, app) }
        for _ in 0..<4 where !open.hasFocus { pressAndWaitForFocusMove(.up, app) }
        XCTAssertTrue(open.hasFocus, "the assistant button has no focus:\n\(app.debugDescription)")
        remote.press(.select)
    }

    func testRequestPlaysAndBackCloses() {
        let app = launch(consent: "1")
        openFromStart(app)
        let field = app.buttons["assistant.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no assistant overlay:\n\(app.debugDescription)")
        XCTAssertTrue(waitForFocus(field), "the text field has no focus:\n\(app.debugDescription)")
        typeOnKeyboard("spiel ZDF", app)
        let send = app.buttons["assistant.send"]
        pressAndWaitForFocusMove(.right, app)
        XCTAssertTrue(send.hasFocus, "Ask has no focus:\n\(app.debugDescription)")
        remote.press(.select)

        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(waitUntil(30) { state.value as? String == "playing" }, "the channel does not play")
        let answer = app.descendants(matching: .any)["assistant.answer"]
        XCTAssertTrue(waitUntil(15) { answer.exists && answer.label.contains("playing") }, "no answer over the player:\n\(app.debugDescription)")
        shot("assistant-answer", app)

        remote.press(.menu)
        let overlay = app.descendants(matching: .any)["assistant.overlay"]
        XCTAssertTrue(waitUntil(5) { !overlay.exists && !field.exists }, "Back did not close the assistant")
        XCTAssertTrue(state.exists, "Back closed the player too")
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not get the focus back")
        _ = mcpCall("stop_playback")
    }

    func testConsentFirstThenAnswer() {
        let app = launch(consent: "0")
        openFromStart(app)
        let agree = app.buttons["assistant.consent.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 10), "no consent before the first request:\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["assistant.field"].exists, "the text field shows before consent")
        shot("assistant-consent", app)
        XCTAssertTrue(waitForFocus(agree), "Agree has no focus:\n\(app.debugDescription)")
        remote.press(.select)

        let field = app.buttons["assistant.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10) && waitForFocus(field), "no text field after consent:\n\(app.debugDescription)")
        typeOnKeyboard("Write me a poem", app)
        pressAndWaitForFocusMove(.right, app)
        remote.press(.select)
        let answer = app.descendants(matching: .any)["assistant.answer"]
        XCTAssertTrue(waitUntil(15) { answer.exists && answer.label.contains("Fernsy") }, "no answer:\n\(app.debugDescription)")
        XCTAssertFalse(app.descendants(matching: .any)["player.state"].exists, "an answer without action started playback")

        remote.press(.menu)
        XCTAssertTrue(waitUntil(5) { !field.exists }, "Back did not close the assistant")
        XCTAssertTrue(app.buttons["assistant.open"].exists, "Back left Start")
    }
}
