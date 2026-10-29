import XCTest

/// Jellyfin's Übersicht as a discovery page (tvos-jellyfin-overview 3.1): the suggestion and
/// "Another Suggestion", the discovery rows, a genre tile opening its grid. The local test
/// Jellyfin with varied copies of its items (JF_TESTMANY).
final class JellyfinOverviewUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func focused(_ prefix: String, _ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", prefix)).firstMatch
    }

    func testDiscoveryPage() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = launchDemo(["IPTV_SERVER": "", "JF_SERVER": "http://127.0.0.1:8097", "JF_USER": "fixture",
                              "JF_PASS": "fixture-pass", "JF_TESTMANY": "80"])
        showTab("Jellyfin", app)
        let spotlight = app.descendants(matching: .any)["jellyfin.spotlight"]
        XCTAssertTrue(spotlight.waitForExistence(timeout: 30), "no suggestion:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["jellyfin.numbers"].exists, "no numbers line")
        shot("overview-top", app)

        // Another suggestion replaces the film.
        let first = spotlight.value as? String
        for _ in 0..<4 where !focused("jellyfin.spotlight.", app).exists { remote.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        // With focus here its backdrop moves (tvos-living-hero 2.3).
        let backdrop = app.descendants(matching: .any)["jellyfin.spotlight.backdrop"]
        XCTAssertTrue(wait(5) { backdrop.value as? String == "moving" }, "the suggestion's backdrop does not move")
        let another = app.buttons["jellyfin.spotlight.another"]
        // By what has focus: the focus follows the remote a moment late.
        for _ in 0..<4 where !another.hasFocus {
            remote.press(app.buttons["jellyfin.spotlight.info"].hasFocus ? .left : .right)
            Thread.sleep(forTimeInterval: 0.8)
        }
        XCTAssertTrue(another.hasFocus, "Another Suggestion has no focus:\n\(app.debugDescription)")
        remote.press(.select)
        XCTAssertTrue(wait(5) { spotlight.value as? String != first }, "the suggestion did not change")

        // Down through the rows to the genre tiles; the discovery rows show on the way.
        var seen: Set<String> = []
        let tile = focused("jellyfin.tile.genre.", app)
        for _ in 0..<12 where !tile.exists {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.6)
            for row in ["favorites", "top", "almost", "short"] where app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "jellyfin.\(row).")).firstMatch.exists {
                seen.insert(row)
            }
        }
        XCTAssertEqual(seen, ["favorites", "top", "almost", "short"], "rows missing")
        XCTAssertTrue(tile.exists, "no genre tile reached:\n\(app.debugDescription)")
        shot("overview-tiles", app)

        // A genre opens its grid; Back returns to Übersicht.
        remote.press(.select)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browse.item.'")).firstMatch.waitForExistence(timeout: 5),
                      "the genre grid did not open:\n\(app.debugDescription)")
        shot("overview-genre", app)
        remote.press(.menu)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Back did not return to the tiles")
    }

    /// tvos-rows-edge-cards 2.1: without moving right, Recently Added shows the poster after the
    /// last whole one at the right screen edge; the first poster stays where the page starts.
    func testNextPosterShowsAtTheEdge() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = launchDemo(["IPTV_SERVER": "", "JF_SERVER": "http://127.0.0.1:8097", "JF_USER": "fixture",
                              "JF_PASS": "fixture-pass", "JF_TESTMANY": "80"])
        showTab("Jellyfin", app)
        let numbers = app.staticTexts["jellyfin.numbers"]
        XCTAssertTrue(numbers.waitForExistence(timeout: 30), "no Übersicht:\n\(app.debugDescription)")
        // The page's start, before the header scrolls away.
        let pageStart = numbers.frame.minX
        // Down to the rows (focus on the first poster keeps every row at its start).
        for _ in 0..<3 { remote.press(.down); Thread.sleep(forTimeInterval: 1) }
        Thread.sleep(forTimeInterval: 2)
        let screen = app.windows.firstMatch.frame
        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jellyfin.item.'")).allElementsBoundByIndex
        let row = posters.filter { $0.frame.minY >= 0 && $0.frame.maxY <= screen.maxY }
        XCTAssertFalse(row.isEmpty, "no poster of Recently Added on screen:\n\(app.debugDescription)")
        let edge = row.first { $0.frame.minX < screen.maxX && $0.frame.maxX > screen.maxX }
        XCTAssertNotNil(edge, "no poster reaches past the right edge: \(row.map { Int($0.frame.minX) })")
        let first = row.map(\.frame.minX).min() ?? 0
        XCTAssertEqual(first, pageStart + 4, accuracy: 3, "the first poster moved away from the page's start")
        shot("edge-poster", app)
    }
}
