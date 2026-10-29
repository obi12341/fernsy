import XCTest

/// The films and series switches (tvos-vod-switch 4.1): switched off in Settings › IPTV Account,
/// the page stays open, films leave the tab bar once Settings is left, and the search and come back when switched on; series switched off
/// at launch have no tab and no Start entries.
final class VODSwitchUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func setFilms(on: Bool, _ app: XCUIApplication) {
        showTab("Settings", app)
        let account = app.buttons["settings.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        let row = app.buttons["settings.iptvMovies"]
        // Back in Settings the first press may only move the focus into the page.
        for _ in 0..<3 where !row.exists {
            for _ in 0..<8 where !account.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
            remote.press(.select)
            _ = row.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(row.exists, "no Films row:\n\(app.debugDescription)")
        for _ in 0..<8 where !row.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(row.hasFocus, "Films has no focus:\n\(app.debugDescription)")
        if (row.value as? String == "on") != on { remote.press(.select) }
        XCTAssertTrue(wait(3) { (row.value as? String == "on") == on }, "Films did not switch")
        // The page stays open (removing a tab used to close it).
        shot("vod-switch-\(on ? "on" : "off")", app)
        XCTAssertTrue(row.exists, "the account page closed after switching:\n\(app.debugDescription)")
        pressAndWaitForFocusMove(.menu, app)
    }

    private func search(_ text: String, _ app: XCUIApplication) {
        showTab("Search", app)
        let field = app.buttons["search.field"]
        for _ in 0..<4 where !field.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(field.hasFocus, "the search field has no focus:\n\(app.debugDescription)")
        typeOnKeyboard(text, app)
    }

    func testSwitchingFilmsOffAndOn() {
        let app = launchDemo()
        let films = app.tabBars.firstMatch.buttons["Movies"]
        XCTAssertTrue(films.waitForExistence(timeout: 30), "no Movies tab")
        setFilms(on: false, app)
        showTab("Start", app)
        XCTAssertTrue(wait(5) { !films.exists }, "the Films tab stays")
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Series"].exists, "Series went with Films")
        search("star", app)
        let stardust = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.vod.m'"))
        XCTAssertFalse(stardust.firstMatch.exists, "the search finds films that are switched off")
        setFilms(on: true, app)
        showTab("Start", app)
        XCTAssertTrue(films.waitForExistence(timeout: 30), "the Films tab does not come back")
        search("star", app)
        XCTAssertTrue(stardust.firstMatch.waitForExistence(timeout: 20), "films are not found again:\n\(app.debugDescription)")
    }

    func testSeriesOffAtLaunch() {
        let app = launchDemo(["IPTV_SHOWSERIES": "0"])
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Movies"].waitForExistence(timeout: 30), "no Movies tab")
        XCTAssertFalse(app.tabBars.firstMatch.buttons["Series"].exists, "a Series tab while series are off")
        let film = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'start.' AND identifier CONTAINS 'movie:'")).firstMatch
        let series = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'start.' AND identifier CONTAINS 'series:'"))
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 30), "Start did not load")
        // Start builds its rows as they come near the screen (tvos-start-scrolling): down through all of them.
        var sawFilm = false
        for _ in 0..<12 {
            sawFilm = sawFilm || film.exists
            XCTAssertEqual(series.count, 0, "Start shows series while they are off")
            pressAndWaitForFocusMove(.down, app, timeout: 1)
        }
        XCTAssertTrue(sawFilm || film.exists, "Start has no films:\n\(app.debugDescription)")
    }
}
