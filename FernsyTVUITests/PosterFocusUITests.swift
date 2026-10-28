import XCTest

/// A watched poster with focus (tvos-poster-focus): the checkmark grows with the poster, not on
/// its own. Demo films 500–507 marked watched (IPTV_TESTRESUME, within the last 90 s).
final class PosterFocusUITests: FernsyUITestCase {
    func testWatchedPosterFocused() {
        let watched = (500...507).map { "movie.\($0):3550:3600" }.joined(separator: ",")
        let app = launchDemo(["IPTV_TESTRESUME": watched])
        showTab("Movies", app)
        let poster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'movie.' AND hasFocus == true")).firstMatch
        for _ in 0..<4 where !poster.exists { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(poster.exists, "no poster focused:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1.5)
        shot("poster-focused", app)
        XCUIRemote.shared.press(.right)
        shot("poster-after-move", app)
    }

    /// A wide card in Continue Watching (a started demo film) with focus.
    func testWideCardFocused() {
        let app = launchDemo(["IPTV_TESTRESUME": "movie.500:1200:3600"])
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'start.resume.' AND hasFocus == true")).firstMatch
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 30))
        for _ in 0..<6 where !card.exists { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(card.exists, "no wide card focused:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1.5)
        shot("widecard-focused", app)
    }
}
