import XCTest

/// A channel without listings in the guide (tvos-guide-empty-channels 2.1): its row has a bar
/// that focus reaches from the row above, and clicking it plays the channel.
final class GuideEmptyChannelsUITests: FernsyUITestCase {
    func testChannelWithoutListingsCanBePlayed() {
        let app = launchDemo(["IPTV_TESTNOEPG": "102"])
        let remote = XCUIRemote.shared
        showLiveView("live.view.guide", app)

        let bar = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.102.gap.'")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "no bar for channel 102:\n\(app.debugDescription)")
        XCTAssertEqual(bar.value as? String, "empty")

        // Down from the switch lands on the rail or a show of the first row (channel 101).
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
        for direction in [XCUIRemote.Button.down, .right, .right] where !focused.exists {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "no show has focus:\n\(app.debugDescription)")
        XCTAssertTrue(focused.identifier.hasPrefix("guide.101."), "focus is not in the first row: \(focused.identifier)")

        // One row down: channel 102's bar.
        remote.press(.down)
        XCTAssertTrue(wait(5) { bar.hasFocus }, "the bar of the channel without listings has no focus:\n\(app.debugDescription)")
        shot("guide-empty-channel", app)

        remote.press(.select)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "channel 102 does not play")
        XCTAssertTrue(mcpCall("now_playing").contains("live:102"), "another channel plays: \(mcpCall("now_playing"))")
    }
}
