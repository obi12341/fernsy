import XCTest

/// Live TV's two views over one source (tvos-live-and-guide 3.2): focus passing the column
/// changes nothing, a category carries from the list into the guide, the guide's rail opens the
/// column, and source and view are kept across launches.
final class LiveAndGuideUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    func testPassingTheColumnKeepsTheSource() {
        let app = launchDemo()
        showLiveView("live.view.list", app)
        let all = app.buttons["live.all"], favorites = app.buttons["live.favorites"]
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        XCTAssertEqual(all.value as? String, "selected", "All Channels is not the source without favourites")
        for _ in 0..<3 where !favorites.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(favorites.hasFocus, "Favourites has no focus:\n\(app.debugDescription)")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(all.value as? String, "selected", "passing the column changed the source")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch.exists,
                      "the rows changed while focus passed Favourites")
    }

    func testACategoryCarriesIntoTheGuide() {
        let app = launchDemo()
        showLiveView("live.view.list", app)
        pickFirstCategory(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the category shows no channels")
        let ids = Set(rows.allElementsBoundByIndex.map { $0.identifier.dropFirst("channel.".count) }.map(String.init))

        showLiveView("live.view.guide", app)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide:\n\(app.debugDescription)")
        let guideIds = Set(cells.allElementsBoundByIndex.map { String($0.identifier.split(separator: ".")[1]) })
        XCTAssertTrue(guideIds.isSubset(of: ids), "the guide shows other channels: \(guideIds) vs \(ids)")
        shot("guide-category", app)
    }

    func testTheRailOpensTheColumn() {
        let app = launchDemo()
        showLiveView("live.view.guide", app)
        let rail = app.buttons["rail.source"]
        XCTAssertTrue(rail.waitForExistence(timeout: 10))
        for direction in [XCUIRemote.Button.down, .left, .left] where !rail.hasFocus {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(rail.hasFocus, "the rail has no focus:\n\(app.debugDescription)")
        shot("rail", app)
        remote.press(.select)
        let all = app.buttons["live.all"], recent = app.buttons["live.recent"]
        XCTAssertTrue(waitUntil(5) { all.hasFocus }, "the column did not open on the chosen source:\n\(app.debugDescription)")
        shot("column", app)
        // Back closes it without a change.
        remote.press(.menu)
        XCTAssertTrue(waitUntil(5) { !all.exists && rail.hasFocus }, "Back did not close the column")
        // Recently Watched (empty in a fresh run): the guide shows no rows, the rail names it.
        remote.press(.select)
        XCTAssertTrue(waitUntil(5) { all.hasFocus })
        remote.press(.up)
        XCTAssertTrue(waitUntil(3) { recent.hasFocus }, "Recently Watched has no focus")
        remote.press(.select)
        XCTAssertTrue(waitUntil(5) { !recent.exists && rail.hasFocus }, "choosing did not close the column")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'")).firstMatch.exists,
                       "the guide still shows channels")
        XCTAssertNotEqual(rail.value as? String, "All Channels")
    }

    func testSourceAndViewAreKept() {
        var app = launchDemo(["IPTV_KEEPLIVE": "1"])
        showLiveView("live.view.guide", app)
        let rail = app.buttons["rail.source"]
        XCTAssertTrue(rail.waitForExistence(timeout: 10))
        for direction in [XCUIRemote.Button.down, .left, .left] where !rail.hasFocus {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        remote.press(.select)
        let allCategories = app.buttons["live.allCategories"]
        XCTAssertTrue(allCategories.waitForExistence(timeout: 5))
        for _ in 0..<6 where !allCategories.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        remote.press(.select)
        pickFocusedTile(app)
        // Back in the guide (the view it came from) with the category.
        XCTAssertTrue(rail.waitForExistence(timeout: 10), "All Categories did not return to the guide")
        let chosen = rail.value as? String ?? ""
        XCTAssertFalse(chosen.isEmpty || chosen == "All Channels", "no category chosen: \(chosen)")
        app.terminate()

        app = launchDemo(["IPTV_KEEPLIVE": "1"])
        showTab("Live TV", app)
        let keptRail = app.buttons["rail.source"]
        XCTAssertTrue(keptRail.waitForExistence(timeout: 30), "Live TV did not open in the guide")
        XCTAssertEqual(keptRail.value as? String, chosen, "the category was not kept")
        XCTAssertEqual(app.buttons["live.view.guide"].value as? String, "selected")
    }

    /// From the list's column: All Categories, then the first tile.
    private func pickFirstCategory(_ app: XCUIApplication) {
        let allCategories = app.buttons["live.allCategories"]
        XCTAssertTrue(allCategories.waitForExistence(timeout: 15))
        for _ in 0..<6 where !allCategories.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(allCategories.hasFocus, "All Categories has no focus:\n\(app.debugDescription)")
        remote.press(.select)
        pickFocusedTile(app)
    }

    private func pickFocusedTile(_ app: XCUIApplication) {
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'category.'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "no category tiles")
        for _ in 0..<4 where !tile.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(tile.hasFocus, "the first tile has no focus:\n\(app.debugDescription)")
        remote.press(.select)
    }
}
