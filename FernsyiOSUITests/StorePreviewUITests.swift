import XCTest

/// The App Store preview of the iPhone and iPad app (store-media): a fixed walk through Start,
/// Live TV with the guide, a film and a series page and the search, with the demo account in the
/// language of STORE_LANGUAGE (TEST_RUNNER_STORE_LANGUAGE). `scripts/store-media.sh previews`
/// records the simulator meanwhile and cuts the video at the activities "store preview start"
/// and "store preview end".
/// Skipped without STORE_LANGUAGE, so regular UI test runs leave it out.
final class StorePreviewUITests: XCTestCase {
    func testPreview() throws {
        let env = ProcessInfo.processInfo.environment
        guard let language = env["STORE_LANGUAGE"] else { throw XCTSkip("only for scripts/store-media.sh previews") }
        let german = language == "de"
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_TAB": "start",
        ]
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", german ? "de_DE" : "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(tab(app, "Live TV").waitForExistence(timeout: 30), "no tabs:\n\(app.debugDescription)")
        // Start's rows and artwork.
        Thread.sleep(forTimeInterval: 4)

        // The marks the script cuts the recording at.
        XCTContext.runActivity(named: "store preview start") { _ in }
        // Each tap or swipe waits about three seconds for the app to settle, which already shows
        // the screen; the pauses only add to the pages worth reading.
        do {
            pause(1.5)
            app.swipeUp(velocity: .slow)
            tab(app, "Live TV").tap()
            app.segmentedControls["live.view"].buttons.element(boundBy: 1).tap()
            pause(0.5)
            app.swipeLeft(velocity: .slow)
            tab(app, "Movies", "Filme").tap()
            app.buttons["movie.500"].tap()
            pause(1.5)
            tab(app, "Series", "Serien").tap()
            app.buttons["series.800"].tap()
            pause(1.5)
            tab(app, "Search", "Suchen").tap()
            let field = app.searchFields.firstMatch
            field.tap()
            field.typeText(german ? "Welt" : "World")
            // The results while typing, and the keyboard out of the way.
            app.swipeDown(velocity: .slow)
            pause(2.5)
        }
        XCTContext.runActivity(named: "store preview end") { _ in }
    }

    /// Real time: the video shows each screen for this long.
    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    /// A tab by its English or German title. No waitForExistence in the walk: each costs about a
    /// second in the video, and tap() waits for the element anyway.
    private func tab(_ app: XCUIApplication, _ names: String...) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", names)).firstMatch
    }
}
