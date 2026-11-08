import XCTest

/// Switching Live TV's source quickly while the guide shows (fix/ios-guide-category-crash): from
/// All Channels, whose archive channels make the axis days long, to Sports without archive and
/// back. The guide kept the drawn hours of the long axis for a moment and built an inverted
/// time range – the app crashed.
final class GuideSourceSwitchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSwitchingCategoriesQuicklyKeepsTheGuide() {
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
        let guide = app.descendants(matching: .any)["guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 30), "no guide:\n\(app.debugDescription)")
        for round in 1...3 {
            choose(app) { $0.buttons["live.allCategories"] }
            let sports = app.buttons["category.3"]
            XCTAssertTrue(sports.waitForExistence(timeout: 10), "no Sports category (round \(round)):\n\(app.debugDescription)")
            sports.tap()
            choose(app) { $0.buttons["All Channels"] }
            XCTAssertEqual(app.state, .runningForeground, "the app crashed in round \(round)")
        }
        XCTAssertTrue(guide.waitForExistence(timeout: 10), "no guide after switching:\n\(app.debugDescription)")
        XCTAssertEqual(app.state, .runningForeground, "the app crashed")
    }

    /// Opens the source menu and taps an entry.
    private func choose(_ app: XCUIApplication, _ entry: (XCUIApplication) -> XCUIElement) {
        let menu = app.buttons["live.sources"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no source menu:\n\(app.debugDescription)")
        menu.tap()
        let item = entry(app).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no menu entry:\n\(app.debugDescription)")
        item.tap()
    }
}
