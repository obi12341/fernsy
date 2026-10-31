import XCTest

/// Back in the film player (tvos-back-closes-overlay 2.2) on the demo server: with the
/// timeline showing Back only hides it, an open subtitle panel closes first, and Back with
/// nothing showing stops. The recording player's steps are checked in RecordingsUITests.
final class BackUITests: FernsyUITestCase {
    func testBackClosesTheTopLayerFirst() {
        let app = launchDemo()
        let remote = XCUIRemote.shared
        let state = app.descendants(matching: .any)["player.state"]
        let timeline = app.staticTexts["vod.remaining"]
        _ = mcpCall("play_item", #"{"item_id":"movie:500","from_start":true}"#)
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the film does not play")
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not take focus:\n\(app.debugDescription)")

        // The timeline: Back hides it, the film keeps playing.
        if !timeline.exists { remote.press(.select) }
        XCTAssertTrue(timeline.waitForExistence(timeout: 5), "no timeline:\n\(app.debugDescription)")
        remote.press(.menu)
        XCTAssertTrue(timeline.waitForNonExistence(timeout: 5), "Back did not hide the timeline")
        XCTAssertEqual(state.value as? String, "playing", "Back with the timeline showing stopped the film")

        // The subtitle panel: Back closes it, the film keeps playing.
        remote.press(.down)
        let panel = app.staticTexts["Subtitles"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "no subtitle panel:\n\(app.debugDescription)")
        shot("subtitle-panel", app)
        remote.press(.menu)
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "Back did not close the panel")
        XCTAssertTrue(state.exists, "Back with the panel open closed the player")

        // Moving showed the timeline again: Back hides it, the next Back stops.
        if timeline.exists {
            remote.press(.menu)
            XCTAssertTrue(timeline.waitForNonExistence(timeout: 5), "Back did not hide the timeline")
            XCTAssertTrue(state.exists, "Back with the timeline showing closed the player")
        }
        remote.press(.menu)
        XCTAssertTrue(wait(10) { !state.exists }, "Back with nothing showing did not stop:\n\(app.debugDescription)")
    }
}
