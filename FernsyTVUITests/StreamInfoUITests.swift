import XCTest

/// Technical information on Apple TV (tvos-stream-info 3.1, 3.2): the panel in the live, film
/// and recording player with `IPTV_SHOWINFO`, the remote still works with it, none by default,
/// and the setting turns it on.
final class StreamInfoUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func panel(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["player.streamInfo"] }

    private func playFirstChannel(_ app: XCUIApplication) -> XCUIElement {
        focusFirstLiveChannel(app)
        remote.press(.select)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the channel does not play")
        return state
    }

    func testPanelInEveryPlayer() {
        let app = launchDemo(["IPTV_SHOWINFO": "1", "IPTV_TESTRECORD": "101:0:20:0:0", "IPTV_FRESHRECORDINGS": "1"])
        let state = playFirstChannel(app)
        XCTAssertTrue(panel(app).waitForExistence(timeout: 5), "no panel in the live player")
        shot("live", app)
        // The remote works as without it: Down opens the channel strip.
        Thread.sleep(forTimeInterval: 2)
        remote.press(.down)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strip.'")).firstMatch.waitForExistence(timeout: 5),
                      "Down did not open the strip with the panel shown")
        shot("live-strip", app)
        _ = mcpCall("stop_playback")
        XCTAssertTrue(wait(10) { !state.exists }, "the player did not close")

        // A film (demo "Stardust").
        _ = mcpCall("play_item", #"{"item_id":"movie:500","from_start":true}"#)
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the film does not play")
        XCTAssertTrue(panel(app).waitForExistence(timeout: 5), "no panel in the film player")
        shot("film", app)
        _ = mcpCall("stop_playback")
        XCTAssertTrue(wait(10) { !state.exists })

        // The 20 s recording of channel 101.
        showTab("Recordings", app)
        let done = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recording.' AND value == 'done'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 60), "the recording did not finish:\n\(app.debugDescription)")
        for _ in 0..<8 where !done.hasFocus {
            remote.press(.down); Thread.sleep(forTimeInterval: 0.4)
            if !done.hasFocus { remote.press(.left); Thread.sleep(forTimeInterval: 0.4) }
        }
        remote.press(.select)
        XCTAssertTrue(wait(15) { state.value as? String == "playing" }, "the recording does not play")
        XCTAssertTrue(panel(app).waitForExistence(timeout: 5), "no panel in the recording player")
        shot("recording", app)
        _ = mcpCall("stop_playback")
    }

    func testNoPanelByDefault() {
        let app = launchDemo()
        _ = playFirstChannel(app)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(panel(app).exists, "a panel without the setting")
        _ = mcpCall("stop_playback")
    }

    func testTheSettingTurnsItOn() {
        let app = launchDemo()
        let row = app.buttons["settings.streamInfo"]
        setStreamInfo(on: true, row, app)
        _ = playFirstChannel(app)
        XCTAssertTrue(panel(app).waitForExistence(timeout: 5), "the setting did not show the panel")
        _ = mcpCall("stop_playback")
        // Leave it off for the other tests (the setting is kept in the simulator).
        setStreamInfo(on: false, row, app)
    }

    private func setStreamInfo(on: Bool, _ row: XCUIElement, _ app: XCUIApplication) {
        showTab("Settings", app)
        let playback = app.buttons["settings.playback"]
        XCTAssertTrue(playback.waitForExistence(timeout: 10))
        for _ in 0..<8 where !playback.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        remote.press(.select)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Technical Info row")
        for _ in 0..<30 where !row.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(row.hasFocus, "Technical Info has no focus:\n\(app.debugDescription)")
        if (row.value as? String == "on") != on { remote.press(.select) }
        XCTAssertTrue(wait(3) { (row.value as? String == "on") == on }, "Technical Info did not switch")
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        remote.press(.menu)
    }
}
