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
}
