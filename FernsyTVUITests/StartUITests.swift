import XCTest

/// Start's rows (tvos-start-rows 2.1): with nothing started the newest film is the large entry and
/// the live, tonight and category rows show; a live card plays its channel; a later show offers
/// to record it.
final class StartUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func focus(_ prefix: String, _ app: XCUIApplication) -> XCUIElement {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30), "no \(prefix) card:\n\(app.debugDescription)")
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", prefix)).firstMatch
        for _ in 0..<8 where !focused.exists { remote.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(focused.exists, "no \(prefix) card has focus:\n\(app.debugDescription)")
        return focused
    }

    func testRowsWithNothingStarted() {
        let app = launchDemo()
        let play = app.buttons["start.hero.resume"]
        XCTAssertTrue(play.waitForExistence(timeout: 30), "no large entry without anything started")
        XCTAssertEqual(play.label, "Play")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'start.live.'")).firstMatch.waitForExistence(timeout: 10), "no On Now row")
        shot("start-top", app)
        // Scroll down row by row for screenshots of the whole page.
        _ = focus("start.live.", app)
        for n in 1...6 {
            pressAndWaitForFocusMove(.down, app)
            shot("start-\(n)", app)
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'start.films.'")).firstMatch.exists, "no film category row")
        // Rows are built as they come near the screen (tvos-start-scrolling): on to the last one.
        let best = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'start.best.'")).firstMatch
        for _ in 0..<8 where !best.exists { remote.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(best.exists, "no Best Rated row")
    }

    func testALiveCardPlaysItsChannel() {
        let app = launchDemo()
        _ = focus("start.live.", app)
        remote.press(.select)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the channel does not play")
        _ = mcpCall("stop_playback")
    }

    func testTonightOffersRecording() {
        let app = launchDemo(["IPTV_FRESHRECORDINGS": "1"])
        let card = focus("start.tonight.", app)
        let id = card.identifier
        remote.press(.select)
        let record = app.sheets.buttons["Record"].firstMatch
        if record.waitForExistence(timeout: 5) {
            remote.press(.menu)
        } else {
            // A show already running plays instead.
            let state = app.descendants(matching: .any)["player.state"]
            XCTAssertTrue(wait(20) { state.exists }, "\(id) neither offers recording nor plays:\n\(app.debugDescription)")
            _ = mcpCall("stop_playback")
        }
    }
}
