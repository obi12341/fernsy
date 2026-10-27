import XCTest

/// Recordings (tvos-live 5.1, 5.2): a short recording finishes, plays from the Recordings tab
/// and is deleted with a long press; a scheduled one shows next to it.
final class RecordingsUITests: FernsyUITestCase {
    func testRecordPlayAndDelete() {
        // 101 from now for 20 s, 102 in ten minutes.
        let app = launchDemo(["IPTV_TESTRECORD": "101:0:20:0:0,102:600:60:0:0", "IPTV_FRESHRECORDINGS": "1"])
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch.waitForExistence(timeout: 30))
        let tab = app.tabBars.firstMatch.buttons["Recordings"]
        for _ in 0..<2 { remote.press(.right); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(wait(5) { tab.hasFocus }, "Recordings tab has no focus")

        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recording.'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "no recordings:\n\(app.debugDescription)")
        // Wait for the 20 s recording to finish (padding 0, 20 s tune-ahead).
        let done = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recording.' AND value == 'done'"))
        XCTAssertTrue(done.firstMatch.waitForExistence(timeout: 60), "the recording did not finish:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recording.' AND value == 'scheduled'")).firstMatch.exists,
                      "the scheduled recording is missing")
        shot("recordings", app)

        let card = done.firstMatch
        let id = card.identifier
        remote.press(.down)
        for _ in 0..<8 where !card.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4); if !card.hasFocus { remote.press(.left); Thread.sleep(forTimeInterval: 0.4) } }
        XCTAssertTrue(card.hasFocus, "the finished recording has no focus:\n\(app.debugDescription)")
        remote.press(.select)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(15) { state.value as? String == "playing" }, "the recording does not play")
        // The player takes focus a moment after it starts; earlier presses go nowhere.
        Thread.sleep(forTimeInterval: 2)
        remote.press(.menu)
        XCTAssertTrue(wait(10) { !state.exists }, "Back did not close the recording:\n\(app.debugDescription)")
        XCTAssertTrue(wait(10) { card.hasFocus }, "focus did not return to the card")

        remote.press(.select, forDuration: 1.5)
        let delete = app.cells.containing(.any, identifier: "trash").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no long-press menu:\n\(app.debugDescription)")
        remote.press(.select)
        XCTAssertTrue(app.buttons[id].waitForNonExistence(timeout: 5), "the recording was not deleted")
    }
}
