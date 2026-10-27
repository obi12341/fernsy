import XCTest

/// The tab bar (tvos-live 2.1, tvos-library 2.1): the app opens on Start, Up reaches the tab bar, Back from a
/// tab's content goes to the tab bar. Each tab is captured as a screenshot attachment.
final class TabsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTabBarFocusAndBack() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
        ]
        app.launch()
        let remote = XCUIRemote.shared
        let start = app.tabBars.firstMatch.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        XCTAssertTrue(waitForFocus(start), "the app did not open on Start")
        showTab("Live TV", app)
        let channel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "Live TV did not open")
        attach("live", app)

        let tabBar = app.tabBars.firstMatch
        let liveTab = tabBar.buttons["Live TV"]
        XCTAssertTrue(liveTab.waitForExistence(timeout: 5), "no tab bar:\n\(app.debugDescription)")
        XCTAssertTrue(waitForFocus(liveTab), "Live TV has no focus:\n\(tabBar.debugDescription)")

        // Down into Live TV, Back returns to the tab bar.
        remote.press(.down)
        XCTAssertTrue(waitForFocusOutside(tabBar, in: app), "Down did not enter Live TV:\n\(app.debugDescription)")
        remote.press(.menu)
        XCTAssertTrue(waitForFocus(liveTab), "Back did not reach the tab bar:\n\(app.debugDescription)")

        // Each tab shows its screen (the pending ones show their title).
        let names = ["Films", "Series", "Recordings", "Search", "Settings"]
        for name in names {
            remote.press(.right)
            XCTAssertTrue(waitForFocus(tabBar.buttons[name]), "\(name) has no focus:\n\(tabBar.debugDescription)")
            let screen = name == "Recordings" ? app.descendants(matching: .any)["recordings.screen"]
                : name == "Films" || name == "Series" ? app.buttons["grid.sort.added"] : name == "Search" ? app.buttons["key.a"] : app.buttons["settings.recordings"]
            XCTAssertTrue(screen.waitForExistence(timeout: 5), "the \(name) screen did not show")
            attach(name, app)
        }
        // Back to Live TV, Down into it, and Up again reaches the tab bar.
        for _ in names { remote.press(.left) }
        XCTAssertTrue(waitForFocus(liveTab), "Live TV has no focus again")
        // The tab's screen follows the focus a moment later.
        XCTAssertTrue(channel.waitForExistence(timeout: 5), "Live TV's screen did not come back")
        Thread.sleep(forTimeInterval: 1)
        // The Live TV screen is shown again first; Down may need a moment.
        var entered = false
        for _ in 0..<3 where !entered {
            remote.press(.down)
            entered = waitForFocusOutside(tabBar, in: app, timeout: 3)
        }
        XCTAssertTrue(entered, "Down did not enter Live TV again:\n\(app.debugDescription)")
        // Up row by row: from the first row it reaches the tab bar.
        for _ in 0..<6 where !liveTab.hasFocus { remote.press(.up); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(waitForFocus(liveTab), "Up did not reach the tab bar:\n\(app.debugDescription)")
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.hasFocus { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Something below the tab bar has focus.
    private func waitForFocusOutside(_ tabBar: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let focus = NSPredicate(format: "hasFocus == true")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let inBar = tabBar.descendants(matching: .any).matching(focus).firstMatch.exists
            let anywhere = app.descendants(matching: .any).matching(focus).firstMatch.exists
            if anywhere && !inBar { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tab-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
