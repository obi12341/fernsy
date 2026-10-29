import XCTest

/// Up and Down move one row at a time (tvos-row-by-row-focus): from a card further right than
/// the row below reaches, Down lands on that row's last card, not on a row further down.
/// Continue Watching gets two demo films (IPTV_TESTRESUME) under the longer On Now row: its cards
/// are as wide as On Now's, and a focused card past the fourth sits at the screen's right edge,
/// so two cards end short of it as three do under a four-card row.
final class RowByRowFocusUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func cards(_ prefix: String, _ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func focused(_ prefix: String, _ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", prefix)).firstMatch
    }

    func testDownOntoAShorterRowAndBackUp() {
        let app = launchDemo(["IPTV_TESTRESUME": "movie.500:600:6000,movie.501:600:6000"])
        XCTAssertTrue(cards("start.live.", app).firstMatch.waitForExistence(timeout: 30), "no On Now row:\n\(app.debugDescription)")
        XCTAssertTrue(cards("start.resume.", app).firstMatch.waitForExistence(timeout: 30), "no Continue Watching row:\n\(app.debugDescription)")
        let live = focused("start.live.", app)
        for _ in 0..<8 where !live.exists { remote.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(live.exists, "no On Now card has focus:\n\(app.debugDescription)")
        let resume = cards("start.resume.", app)
        XCTAssertEqual(resume.count, 2, "Continue Watching does not have two cards:\n\(app.debugDescription)")
        let lastResume = resume.allElementsBoundByIndex.max { $0.frame.maxX < $1.frame.maxX }!
        // Right along On Now until the focused card starts past the last Continue Watching card.
        for _ in 0..<10 where live.frame.minX <= lastResume.frame.maxX { pressAndWaitForFocusMove(.right, app) }
        XCTAssertGreaterThan(live.frame.minX, lastResume.frame.maxX, "no On Now card past Continue Watching: \(focusKey(app))")
        let upper = live.identifier
        shot("on-now-right", app)

        pressAndWaitForFocusMove(.down, app)
        shot("after-down", app)
        XCTAssertTrue(waitForFocus(lastResume), "Down from \(upper) did not land on Continue Watching's last card \(lastResume.identifier): \(focusKey(app))")

        pressAndWaitForFocusMove(.up, app)
        XCTAssertTrue(wait(5) { live.exists }, "Up from Continue Watching did not return to On Now: \(focusKey(app))")
    }
}
