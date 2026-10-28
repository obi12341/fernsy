import XCTest

/// Scrolling on the Jellyfin tab (tvos-edge-scrolling): screenshots while a row on Overview moves
/// sideways and while the Films grid moves down, to see the posters at the screen edges and
/// below the view switcher. The local test Jellyfin with its items repeated (JF_TESTMANY).
final class JellyfinEdgesUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    /// At once, mid-animation: shot() waits a second first.
    private func now(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testEdgesWhileScrolling() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = launchDemo(["IPTV_SERVER": "", "JF_SERVER": "http://127.0.0.1:8097", "JF_USER": "fixture",
                              "JF_PASS": "fixture-pass", "JF_TESTMANY": "60"])
        showTab("Jellyfin", app)
        let item = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jellyfin.item.'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 30), "no Jellyfin items:\n\(app.debugDescription)")
        // Overview: into the Recently Added row and along it.
        for _ in 0..<4 where !app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jellyfin.item.' AND hasFocus == true")).firstMatch.exists {
            remote.press(.down); Thread.sleep(forTimeInterval: 0.5)
        }
        for step in 0..<7 {
            remote.press(.right)
            Thread.sleep(forTimeInterval: step == 6 ? 0.15 : 0.5)
        }
        now("edges-row-moving", app)
        Thread.sleep(forTimeInterval: 1)
        now("edges-row-still", app)
        // Films: down the grid, under the view switcher.
        let films = app.buttons["jellyfin.view.films"]
        let pills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jellyfin.view.' AND hasFocus == true")).firstMatch
        for _ in 0..<4 where !pills.exists { remote.press(.up); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(pills.exists, "the view switcher has no focus:\n\(app.debugDescription)")
        for _ in 0..<6 where !films.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        for _ in 0..<6 where !films.hasFocus { remote.press(.left); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(films.hasFocus, "Films has no focus:\n\(app.debugDescription)")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1.5)
        for step in 0..<4 {
            remote.press(.down)
            Thread.sleep(forTimeInterval: step == 3 ? 0.15 : 0.6)
        }
        now("edges-grid-moving", app)
        Thread.sleep(forTimeInterval: 1)
        now("edges-grid-still", app)
    }
}
