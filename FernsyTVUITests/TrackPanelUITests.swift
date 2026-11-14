import XCTest

/// Long track lists in the player (fix/tv-track-list-scroll) on the demo server: with 30 extra
/// subtitle tracks (IPTV_TESTSUBTRACKS) the panel scrolls to the last one, and opens again on
/// the track in use.
final class TrackPanelUITests: FernsyUITestCase {
    func testLongSubtitleListScrolls() {
        let count = 30
        let app = launchDemo(["IPTV_TESTSUBTRACKS": String(count)])
        let remote = XCUIRemote.shared
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(waitForLog(" films, ", timeout: 30), "the films did not load")
        _ = mcpCall("play_item", #"{"item_id":"movie:500","from_start":true}"#)
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the film does not play")
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not take focus:\n\(app.debugDescription)")

        remote.press(.down)
        let panel = app.staticTexts["Subtitles"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "no subtitle panel:\n\(app.debugDescription)")
        let last = app.buttons["Test \(count)"]
        XCTAssertTrue(last.waitForExistence(timeout: 5), "the test tracks are not in the panel:\n\(app.debugDescription)")
        // From "Off" past the film's own tracks to the last test track.
        for _ in 0..<(count + 5) where !last.hasFocus { remote.press(.down) }
        XCTAssertTrue(wait(3) { last.hasFocus }, "the last track cannot be reached:\n\(app.debugDescription)")
        XCTAssertTrue(app.frame.contains(last.frame), "the focused track is off screen: \(last.frame)")
        XCTAssertTrue(panel.exists && app.frame.contains(panel.frame), "the heading left the screen: \(panel.frame)")
        shot("subtitle-panel-end", app)

        // Chosen: the panel closes; opened again it shows that track with focus.
        remote.press(.select)
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "choosing a track did not close the panel")
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not take focus back")
        remote.press(.down)
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the panel did not open again")
        XCTAssertTrue(wait(3) { last.hasFocus }, "the panel did not open on the track in use:\n\(app.debugDescription)")
        XCTAssertTrue(app.frame.contains(last.frame), "the track in use is off screen: \(last.frame)")
        shot("subtitle-panel-reopened", app)
        XCTAssertEqual(state.value as? String, "playing", "the film stopped")
    }
}
