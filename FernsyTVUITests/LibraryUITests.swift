import XCTest

/// Films and series (tvos-library 3.2–3.4): the grid sorts by rating, scrolling does not load
/// posters twice, a film page resumes or starts over, a series page names the next episode.
final class LibraryUITests: FernsyUITestCase {
    func testFilmGridSortsAndKeepsPosters() {
        let app = launchDemo(["IPTV_FRESHIMAGES": "1"])
        let films = app.tabBars.firstMatch.buttons["Films"]
        XCTAssertTrue(films.waitForExistence(timeout: 30))
        for _ in 0..<6 where !films.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(films.hasFocus)
        let rating = app.buttons["grid.sort.rating"]
        XCTAssertTrue(rating.waitForExistence(timeout: 10))
        shot("films", app)
        // Down lands in the grid; Up from its first row reaches the sorting, then sideways to Rating.
        // Down from the tab bar reaches the header (category and sorting); Rating is to the right.
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        for direction in [XCUIRemote.Button.right, .right, .right, .left, .left, .left, .left] where !rating.hasFocus {
            XCUIRemote.shared.press(direction)
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(rating.hasFocus, "the Rating sort has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 1)
        shot("films-rating", app)
        // The first poster now has the highest rating of the visible ones.
        let ratings = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'movie.'")).allElementsBoundByIndex.prefix(14)
            .compactMap { Double($0.label.components(separatedBy: ",").first?.replacingOccurrences(of: "★ ", with: "") ?? "") }
        XCTAssertFalse(ratings.isEmpty, "no ratings on the posters")
        XCTAssertEqual(ratings.first, ratings.max(), "the grid is not sorted by rating: \(ratings)")
        // Scroll through the grid and back: posters come from the cache the second time.
        for _ in 0..<6 { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        // Up row by row until focus leaves the grid: it lands in the header, not in the tab bar.
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<8 where focused.identifier.hasPrefix("movie.") {
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertFalse(app.tabBars.firstMatch.buttons["Films"].hasFocus, "Up from the grid skipped the sorting: \(focused.identifier)")
        // No poster was loaded twice while scrolling.
        let loads = appLog("image loaded")
        XCTAssertFalse(loads.isEmpty, "no image loads logged")
        XCTAssertEqual(Set(loads.map { $0.components(separatedBy: "image loaded: ").last ?? "" }).count, loads.count, "posters loaded twice")
    }
}

/// Film and series pages on the local test Jellyfin (tvos-library 3.3, 3.4): Resume starts at
/// the server's position, From the Beginning at 0; the series offers the next unwatched episode.
/// Needs scripts/jellyfin-test-server.sh and a resume position on the fixture film (play it past 2 min).
final class DetailPagesUITests: FernsyUITestCase {
    private func launchJellyfin() -> XCUIApplication {
        launchDemo(["IPTV_SERVER": "", "JF_SERVER": "http://127.0.0.1:8097", "JF_USER": "fixture", "JF_PASS": "fixture-pass"])
    }

    private func openJellyfinItem(named name: String, _ app: XCUIApplication) {
        let tab = app.tabBars.firstMatch.buttons["Jellyfin"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        for _ in 0..<3 where !tab.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        let item = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jellyfin.item.' AND label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15), "no \(name):\n\(app.debugDescription)")
        for _ in 0..<10 where !item.hasFocus {
            XCUIRemote.shared.press(item.frame.minY > 500 ? .down : .right)
            Thread.sleep(forTimeInterval: 0.4)
            if !item.hasFocus && !app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.identifier.hasPrefix("jellyfin.item.") {
                XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.4)
            }
        }
        XCTAssertTrue(item.hasFocus, "\(name) has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
    }

    private func position() -> Int {
        let text = mcpCall("now_playing")
        guard let range = text.range(of: #""position_seconds" *: *([0-9]+)"#, options: .regularExpression) else { return -1 }
        return Int(text[range].split(separator: ":").last!.trimmingCharacters(in: .whitespaces)) ?? -1
    }

    func testFilmResumesAndStartsOver() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = launchJellyfin()
        openJellyfinItem(named: "Fixture Film", app)
        let play = app.buttons["film.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "no film page")
        XCTAssertTrue(play.label.contains("Resume"), "no Resume on a partly watched film: \(play.label)")
        shot("film", app)
        XCTAssertTrue(wait(5) { play.hasFocus } || { XCUIRemote.shared.press(.down); return wait(3) { play.hasFocus } }())
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(20) { self.position() > 100 }, "Resume did not start at the server's position (\(position()))")
        Thread.sleep(forTimeInterval: 2)
        XCUIRemote.shared.press(.menu)
        let fromStart = app.buttons["film.fromStart"]
        XCTAssertTrue(fromStart.waitForExistence(timeout: 10))
        for _ in 0..<3 where !fromStart.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(20) { (0...15).contains(self.position()) }, "From the Beginning did not start at 0 (\(position()))")
        // Back at about two minutes, so the next run still has a resume position.
        _ = mcpCall("seek", #"{"by_seconds":150}"#)
        Thread.sleep(forTimeInterval: 3)
        XCUIRemote.shared.press(.menu)
    }

    func testSeriesOffersTheNextEpisode() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = launchJellyfin()
        let tab = app.tabBars.firstMatch.buttons["Jellyfin"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        for _ in 0..<3 where !tab.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        let seriesView = app.buttons["jellyfin.view.series"]
        XCTAssertTrue(seriesView.waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.down)
        for direction in [XCUIRemote.Button.right, .right, .right, .left, .left] where !seriesView.hasFocus {
            XCUIRemote.shared.press(direction); Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(seriesView.hasFocus, "Series view has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        let show = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jellyfin.item.'")).firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(wait(5) { show.hasFocus }, "the series has no focus")
        XCUIRemote.shared.press(.select)
        let next = app.buttons["series.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "no Next Episode:\n\(app.debugDescription)")
        shot("series", app)
        XCTAssertTrue(next.label.contains("S1 F3"), "the next episode is not S1 F3: \(next.label)")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode.' AND value == 'next'")).firstMatch.exists,
                      "no episode is marked Up Next")
    }

    /// A demo series whose S1 F2 is partly watched (IPTV_TESTRESUME) offers S1 F2 next.
    func testDemoSeriesOffersTheStartedEpisode() {
        let app = launchDemo(["IPTV_TESTRESUME": "episode.00101:300:2760"])
        let tab = app.tabBars.firstMatch.buttons["Series"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        for _ in 0..<6 where !tab.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        let show = app.buttons["series.800"]
        XCTAssertTrue(show.waitForExistence(timeout: 15), "no demo series 800")
        for _ in 0..<12 where !show.hasFocus {
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            XCUIRemote.shared.press(focused.identifier.hasPrefix("series.") ? (focused.frame.midX > show.frame.midX ? .left : .right) : .down)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(show.hasFocus, "series 800 has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        let next = app.buttons["series.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "no Next Episode")
        XCTAssertTrue(next.label.contains("S1 F2"), "the next episode is not S1 F2: \(next.label)")
    }
}

/// The Jellyfin tab (tvos-library 3.5) with the server stopped: the cached lists show with the
/// note that the server cannot be reached. Run with the test Jellyfin stopped
/// (docker stop fernsy-jf-fixtures); JF_CACHEONLY restores the session from the cache.
final class JellyfinOfflineUITests: FernsyUITestCase {
    func testCachedListsWhenTheServerIsDown() throws {
        try XCTSkipIf(jellyfinRunning(), "the test Jellyfin runs; stop it for this test (docker stop fernsy-jf-fixtures)")
        let app = launchDemo(["IPTV_SERVER": "", "JF_CACHEONLY": "http://127.0.0.1:8097|3dd68e56e17d49f6ba0546bd13d19852|3eb16930ee7841249860eaa07e3ebb23"])
        let tab = app.tabBars.firstMatch.buttons["Jellyfin"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        for _ in 0..<3 where !tab.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(app.staticTexts["jellyfin.offline"].waitForExistence(timeout: 30), "no offline note:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jellyfin.item.'")).firstMatch.exists, "no cached items")
        shot("jellyfin-offline", app)
    }
}
