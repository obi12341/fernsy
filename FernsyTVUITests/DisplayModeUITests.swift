import XCTest

/// Matching the TV's display mode (tvos-match-content 3.1, 4.3) on the demo server: the IPTV
/// account's switch is off by default and then nothing asks; turned on, the full-screen player
/// asks tvOS for the shown frame rate and dynamic range, the Live TV preview does not, and
/// closing the player releases the mode. The simulator never switches, so the tests read the
/// requests from the app's log. Jellyfin's switch is checked on the real Apple TV (4.4).
final class DisplayModeUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func state(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["player.state"] }

    private func playFilm(_ app: XCUIApplication) {
        _ = mcpCall("play_item", #"{"item_id":"movie:500","from_start":true}"#)
        XCTAssertTrue(wait(30) { self.state(app).value as? String == "playing" }, "the film does not play")
    }

    private func stopPlayback(_ app: XCUIApplication) {
        _ = mcpCall("stop_playback")
        XCTAssertTrue(wait(10) { !self.state(app).exists }, "the player did not close")
    }

    func testIPTVSwitchOffByDefault() {
        let app = launchDemo()
        let row = app.buttons["settings.iptvMatchDisplayMode"]
        openAccountSettings(row, app)
        XCTAssertEqual(row.value as? String, "off", "the IPTV account's switch is not off by default")
        shot("iptv-off", app)
        leaveSettings(app)

        playFilm(app)
        XCTAssertTrue(appLog("display mode:").isEmpty, "asked with the IPTV switch off: \(appLog("display mode:"))")
        stopPlayback(app)
    }

    func testOnTheFilmAsksThePreviewDoesNot() {
        let app = launchDemo()
        let row = app.buttons["settings.iptvMatchDisplayMode"]
        setSwitch(on: true, row, app)

        _ = focusFirstLiveChannel(app)
        XCTAssertTrue(waitForLog("preview channel"), "the preview did not start")
        // The preview's first picture would be the moment it asked.
        XCTAssertTrue(waitForLog("stats ", timeout: 20), "the preview shows no picture")
        XCTAssertTrue(appLog("display mode:").isEmpty, "the preview asked for a display mode: \(appLog("display mode:"))")

        playFilm(app)
        let asked = appLog("display mode: ")
        XCTAssertTrue(asked.contains { $0.contains(" Hz ") }, "no request with a frame rate: \(asked)")
        shot("film", app)
        _ = mcpCall("stop_playback")
        XCTAssertTrue(waitForLog("display mode: released", timeout: 10), "closing the player did not release the mode")

        // Leave it off for the other tests (the setting is kept in the simulator).
        setSwitch(on: false, row, app)
    }

    private func setSwitch(on: Bool, _ row: XCUIElement, _ app: XCUIApplication) {
        openAccountSettings(row, app)
        if (row.value as? String == "on") != on { remote.press(.select) }
        XCTAssertTrue(wait(3) { (row.value as? String == "on") == on }, "the switch did not change")
        leaveSettings(app)
    }

    private func openAccountSettings(_ row: XCUIElement, _ app: XCUIApplication) {
        showTab("Settings", app)
        let account = app.buttons["settings.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        for _ in 0..<8 where !account.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        remote.press(.select)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Match Frame Rate and Dynamic Range row")
        for _ in 0..<20 where !row.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(row.hasFocus, "the row has no focus:\n\(app.debugDescription)")
    }

    private func leaveSettings(_ app: XCUIApplication) {
        pressAndWaitForFocusMove(.menu, app)
        remote.press(.menu)
    }
}
