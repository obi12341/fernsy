import XCTest

/// Search (tvos-library 4.1): the letter row writes the query; typed text finds live shows and
/// films; a running show plays its channel; shows of hidden channels are not found.
final class SearchUITests: FernsyUITestCase {
    private func openSearch(_ app: XCUIApplication) {
        let tab = app.tabBars.firstMatch.buttons["Search"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        for _ in 0..<12 where !tab.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(tab.hasFocus, "the search tab has no focus")
        XCTAssertTrue(app.buttons["key.a"].waitForExistence(timeout: 10), "no letter row")
    }

    private func type(_ text: String, _ app: XCUIApplication) {
        let field = app.textFields["search.field"]
        for _ in 0..<4 where !field.hasFocus { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(field.hasFocus, "the search field has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        app.typeText(text)
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 2)
    }

    func testFindAndPlay() {
        let app = launchDemo()
        openSearch(app)
        // The letter row: "a" then delete.
        XCUIRemote.shared.press(.down)
        let a = app.buttons["key.a"]
        for _ in 0..<30 where !a.hasFocus { XCUIRemote.shared.press(.left); Thread.sleep(forTimeInterval: 0.15) }
        XCTAssertTrue(a.hasFocus, "key a has no focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(3) { app.descendants(matching: .any)["search.query"].value as? String == "a" }, "the letter row did not write")
        for _ in 0..<31 { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.1) }
        XCUIRemote.shared.press(.select)   // delete
        XCTAssertTrue(wait(3) { app.descendants(matching: .any)["search.query"].value as? String == "" }, "delete did not remove the letter")

        type("world report", app)
        let live = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.live.'"))
        XCTAssertTrue(live.firstMatch.waitForExistence(timeout: 20), "no live results:\n\(app.debugDescription)")
        shot("search", app)
    }

    func testFilmsAreFound() {
        let app = launchDemo()
        openSearch(app)
        XCUIRemote.shared.press(.down)
        type("star", app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.vod.' AND label CONTAINS 'Stardust'")).firstMatch
            .waitForExistence(timeout: 15), "the film Stardust was not found:\n\(app.debugDescription)")
    }

    func testRunningShowPlaysItsChannel() {
        let app = launchDemo()
        openSearch(app)
        XCUIRemote.shared.press(.down)
        type("the", app)
        let now = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.live.' AND label CONTAINS 'on now'")).firstMatch
        XCTAssertTrue(now.waitForExistence(timeout: 20), "no running show found")
        // Down from the field reaches the live row; any show on now will do.
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(focused.identifier.hasPrefix("search.live.") && focused.label.contains("on now"),
                      "focus is not on a show on now: \(focused.identifier) \(focused.label)")
        XCUIRemote.shared.press(.select)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(20) { state.exists && state.value as? String == "playing" }, "the channel does not play")
    }

    func testHiddenChannelsAreNotFound() {
        let app = launchDemo(["IPTV_TESTHIDE": "category:1"])
        openSearch(app)
        XCUIRemote.shared.press(.down)
        type("world report", app)
        Thread.sleep(forTimeInterval: 4)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.live.'")).firstMatch.exists,
                       "shows of the hidden News channels were found")
    }
}

/// From Start into a film page and play; a film found by search opens its page (tvos-library 5.1).
final class StartAndSearchFlowUITests: FernsyUITestCase {
    func testStartOpensTheFilmAndPlays() {
        let app = launchDemo(["IPTV_TESTRESUME": "movie.500:600:3600"])
        let info = app.buttons["start.hero.info"]
        XCTAssertTrue(info.waitForExistence(timeout: 30), "no large entry on Start")
        XCUIRemote.shared.press(.down)
        for _ in 0..<3 where !info.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(info.hasFocus, "the info button has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        // The demo films are 52 s long, too short for a valid resume position: play from the start.
        let fromStart = app.buttons["film.fromStart"]
        XCTAssertTrue(fromStart.waitForExistence(timeout: 10), "no film page with From the Beginning")
        for _ in 0..<3 where !fromStart.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(fromStart.hasFocus, "From the Beginning has no focus")
        XCUIRemote.shared.press(.select)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(20) { state.exists && state.value as? String == "playing" }, "the film does not play")
    }

    func testSearchOpensAFilm() {
        let app = launchDemo()
        let tab = app.tabBars.firstMatch.buttons["Search"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        for _ in 0..<12 where !tab.hasFocus { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<4 where !field.hasFocus { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCUIRemote.shared.press(.select)
        app.typeText("stardust")
        XCUIRemote.shared.press(.menu)
        let hit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.vod.' AND label CONTAINS 'Stardust'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 15), "Stardust was not found")
        for _ in 0..<4 where !hit.hasFocus { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(hit.hasFocus, "the hit has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["film.play"].waitForExistence(timeout: 10), "the film page did not open")
    }
}
