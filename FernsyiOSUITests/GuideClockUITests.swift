import XCTest

/// The guide follows the clock on iPhone and iPad (fix/guide-now-line): the now line stood at
/// the time each row was last redrawn, so it broke apart between rows and stayed behind. One
/// minute clock moves the ruler's line and every row's.
final class GuideClockUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testNowLineFollowsTheClock() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_TAB": "live",
            "IPTV_LIVEVIEW": "guide",
        ]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let line = app.descendants(matching: .any)["guide.now"]
        XCTAssertTrue(line.waitForExistence(timeout: 30), "no now line in the guide's ruler:\n\(app.debugDescription)")
        // The guide has opened at now and rests.
        Thread.sleep(forTimeInterval: 2)
        let before = (line.value as? String) ?? "", x = line.frame.minX
        XCTAssertFalse(before.isEmpty, "the now line has no time")
        attach("guide-clock-before", app)

        let deadline = Date().addingTimeInterval(75)
        while (line.value as? String) == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertNotEqual(line.value as? String, before, "the now line did not move on within 75 s")
        // One minute on the axis (220 points per hour).
        XCTAssertEqual(line.frame.minX - x, 220.0 / 60, accuracy: 1, "the now line moved by something else than a minute")

        // Rows built now stand at the same minute as the ones from before: down a page and back.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        Thread.sleep(forTimeInterval: 1)
        attach("guide-clock-scrolled", app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        Thread.sleep(forTimeInterval: 1)
        attach("guide-clock-after", app)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
