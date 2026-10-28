import XCTest

/// Fast scrolling through loading rows (tvos-guide-focus-while-loading 2.1): when a row's
/// programme arrives while its loading bar has focus, focus stays in that row.
final class GuideFocusUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    /// The channel id of the guide cell with focus ("guide.<channel>.<start>" or ".gap.").
    private func focusedChannel(_ app: XCUIApplication) -> Int? {
        let cell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
        guard cell.exists else { return nil }
        return Int(cell.identifier.split(separator: ".").dropFirst().first ?? "")
    }

    func testFocusStaysInTheRowWhileItLoads() {
        let app = launchDemo(["IPTV_TESTEPGDELAY": "15"])
        showLiveView("live.view.guide", app)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide cells")
        for direction in [XCUIRemote.Button.down, .right, .right] where focusedChannel(app) == nil {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertNotNil(focusedChannel(app), "no guide cell has focus:\n\(app.debugDescription)")
        // Down quickly into rows that still load (each takes 15 s).
        for _ in 0..<12 { remote.press(.down); Thread.sleep(forTimeInterval: 0.15) }
        Thread.sleep(forTimeInterval: 1)
        guard let reached = focusedChannel(app) else { return XCTFail("focus left the guide:\n\(app.debugDescription)") }
        let loadingRows = app.buttons.matching(NSPredicate(format: "value == 'loading'")).allElementsBoundByIndex.map(\.identifier)
        let loading = "\(reached) reached; loading: \(loadingRows)"
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == 'loading'", "guide.\(reached).")).firstMatch.exists,
                      "the row reached had already loaded (\(loading)); the test did not reach a loading row")
        // Its programme arrives: focus stays in the row.
        Thread.sleep(forTimeInterval: 18)
        XCTAssertEqual(focusedChannel(app), reached, "focus left the row \(reached) when its programme arrived")
        shot("guide-focus-after-load", app)
        XCTAssertFalse(appLog("focus kept").isEmpty, "the row did not hand focus over")
    }
}
