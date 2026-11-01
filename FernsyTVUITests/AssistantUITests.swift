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
        // From the tab bar, Down may pass the pill and land on the large entry's Play; Start then
        // scrolls and the lazy stack drops the pill, so go back up instead of further down.
        if !open.hasFocus { pressAndWaitForFocusMove(.down, app) }
        for _ in 0..<3 where !open.hasFocus { pressAndWaitForFocusMove(.up, app) }
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

    /// The real model through the dev relay (cloud-assistant 5.2): opt-in, it costs model calls.
    /// `TEST_RUNNER_FERNSY_ASSISTANT_LIVE=<DEV_TOKEN> scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/AssistantUITests/testRealModel"`
    /// (token in ~/.config/fernsy/dev-token). A request by channel name plays it, a request to
    /// record schedules the show, an off-topic request is declined without an action.
    func testRealModel() throws {
        let token = ProcessInfo.processInfo.environment["FERNSY_ASSISTANT_LIVE"] ?? ""
        try XCTSkipIf(token.isEmpty, "opt-in: TEST_RUNNER_FERNSY_ASSISTANT_LIVE=<dev token>")
        let app = launchDemo(["IPTV_CLOUD": "https://fernsy-cloud-dev.mobilistics.workers.dev", "IPTV_CLOUDTOKEN": token,
                              "IPTV_ASSISTANT_CONSENT": "1", "IPTV_FRESHRECORDINGS": "1"],
                             arguments: ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"])
        func ask(_ text: String) -> String {
            let field = app.buttons["assistant.field"]
            XCTAssertTrue(field.waitForExistence(timeout: 10) && waitForFocus(field), "no text field:\n\(app.debugDescription)")
            typeOnKeyboard(text, app)
            pressAndWaitForFocusMove(.right, app)
            remote.press(.select)
            let answer = app.descendants(matching: .any)["assistant.answer"]
            XCTAssertTrue(waitUntil(60) { answer.exists && !answer.label.isEmpty }, "no answer to \(text):\n\(app.debugDescription)")
            return answer.label
        }

        openFromStart(app)
        let playing = ask("Spiel Northern Light 1")
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(waitUntil(30) { state.value as? String == "playing" }, "the channel does not play; answer: \(playing)")
        XCTAssertTrue(mcpCall("now_playing").contains("live:101"), "not Northern Light 1: \(mcpCall("now_playing"))")
        shot("assistant-real-play", app)
        remote.press(.menu)
        _ = mcpCall("stop_playback")

        XCTAssertTrue(waitUntil(15) { app.buttons["assistant.open"].exists }, "not back on Start")
        openFromStart(app)
        let scheduled = ask("Nimm die nächste Sendung auf World View 24 auf")
        // The raw JSON-RPC answer: the result's JSON appears escaped and compact, so match loosely.
        XCTAssertTrue(waitUntil(15) { self.mcpCall("list_recordings").range(of: #"channel_id\\?"\s*:\s*103\b"#, options: .regularExpression) != nil },
                      "nothing scheduled on World View 24; answer: \(scheduled)\n\(mcpCall("list_recordings"))")
        shot("assistant-real-record", app)

        let declined = ask("Schreib mir ein Gedicht über Katzen")
        XCTAssertTrue(declined.contains("Fernsy"), "not declined: \(declined)")
        XCTAssertFalse(state.exists && state.value as? String == "playing", "an off-topic request started playback")
    }
}

