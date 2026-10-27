import XCTest

/// Live TV (tvos-live 3.2, 3.3): the pane previews the focused channel; with a single-stream
/// account whose stream a recording holds, it shows no preview; long press hides a channel.
final class LiveTVUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
        ].merging(extra) { $1 }
        app.launch()
        return app
    }

    private func focusFirstChannel(_ app: XCUIApplication) -> XCUIElement {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30), "no channels")
        for _ in 0..<3 where !first.hasFocus {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(first.hasFocus, "the first channel has no focus:\n\(app.debugDescription)")
        return first
    }

    func testPreviewOfTheFocusedChannel() {
        let app = launch()
        _ = focusFirstChannel(app)
        XCTAssertTrue(app.otherElements["live.preview"].waitForExistence(timeout: 15), "no preview in the pane")
    }

    func testNoPreviewWhileARecordingHoldsTheOnlyStream() {
        // Channel 102 is recorded from now for two minutes; the account allows one stream.
        let app = launch(["IPTV_MAXCONN": "1", "IPTV_TESTRECORD": "102:0:120:0:0"])
        let row = app.buttons["channel.101"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        _ = focusFirstChannel(app)
        Thread.sleep(forTimeInterval: 4)
        XCTAssertFalse(app.otherElements["live.preview"].exists, "a preview opened a second stream")
    }

    func testHidingAChannel() {
        let app = launch()
        let first = focusFirstChannel(app)
        let id = first.identifier
        XCUIRemote.shared.press(.select, forDuration: 1.5)
        // tvOS shows the menu entries as cells, each holding its symbol ("eye.slash": Hide).
        let hide = app.cells.containing(.any, identifier: "eye.slash").firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "no long-press menu:\n\(app.debugDescription)")
        for _ in 0..<4 where !hide.hasFocus { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(hide.hasFocus, "Hide has no focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons[id].waitForNonExistence(timeout: 5), "\(id) is still listed")

        // Not in the guide either, and not in the player's channel strip.
        let channelId = id.dropFirst("channel.".count)
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.right)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "guide.\(channelId).")).firstMatch.exists,
                       "the hidden channel is in the guide")
        XCUIRemote.shared.press(.left)
        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        for _ in 0..<3 where !next.hasFocus { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1) }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["player.state"].waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strip.'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["strip.\(channelId)"].exists, "the hidden channel is in the strip")
    }
}

/// All categories (tvos-live 3.4): a long press pins a category into Live TV's column.
final class AllCategoriesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testPinningACategory() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
        ]
        app.launch()
        let remote = XCUIRemote.shared
        let all = app.buttons["live.allCategories"]
        XCTAssertTrue(all.waitForExistence(timeout: 30))
        // From the tab bar down into Live TV, then left into the column and down to "All Categories".
        remote.press(.down)
        for _ in 0..<3 { remote.press(.left); Thread.sleep(forTimeInterval: 0.3) }
        for _ in 0..<6 where !all.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(all.hasFocus, "All Categories has no focus:\n\(app.debugDescription)")
        remote.press(.select)

        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'category.'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "no category tiles")
        for _ in 0..<4 where !tile.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(tile.hasFocus, "the first tile has no focus:\n\(app.debugDescription)")
        let id = String(tile.identifier.dropFirst("category.".count))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "all-categories"
        shot.lifetime = .keepAlways
        add(shot)

        remote.press(.select, forDuration: 1.5)
        let pin = app.cells.containing(.any, identifier: "pin").firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "no long-press menu:\n\(app.debugDescription)")
        remote.press(.select)
        remote.press(.menu)
        XCTAssertTrue(app.buttons["live.category.\(id)"].waitForExistence(timeout: 5),
                      "the pinned category is not in the column:\n\(app.debugDescription)")
    }
}
