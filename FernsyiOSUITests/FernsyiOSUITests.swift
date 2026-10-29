import XCTest

/// UI tests of the iPhone and iPad app against the demo server (ios-app): real touch input for
/// the tabs, the live and film players, the channel panel and the search. The app's debug MCP
/// server (port 52326) reads its state and log.
final class FernsyiOSUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchDemo(_ extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
        ].merging(extra) { $1 }
        // English, whatever the simulator's language: the demo server answers in the app's
        // language, and the tests look for English titles.
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    /// A tab by its English or German title (the simulator's language decides).
    private func tab(_ app: XCUIApplication, _ names: String...) -> XCUIElement {
        // On iPad the tab bar and the sidebar both have the title: the first one.
        for name in names {
            let button = app.tabBars.buttons[name].firstMatch
            if button.waitForExistence(timeout: 2) { return button }
            let any = app.buttons.matching(identifier: name).firstMatch
            if any.exists { return any }
            let labelled = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
            if labelled.exists { return labelled }
        }
        return app.buttons[names[0]].firstMatch
    }

    private func waitForState(_ app: XCUIApplication, _ value: String, timeout: TimeInterval = 20) -> Bool {
        let state = app.descendants(matching: .any)["player.state"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state.exists, (state.value as? String) == value { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// Calls a tool of the app's debug MCP server and returns the raw answer.
    private func mcp(_ tool: String, _ arguments: String = "{}") -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:52326/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        var text = "no answer"
        URLSession.shared.dataTask(with: request) { data, _, _ in
            text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no data"
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        return text
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Shows the player's controls (a tap toggles them). The player turns an iPhone to landscape
    /// by itself; the test device follows, or taps and swipes land at portrait coordinates.
    private func showControls(_ app: XCUIApplication) {
        if UIDevice.current.userInterfaceIdiom == .phone, XCUIDevice.shared.orientation != .landscapeLeft {
            // Device landscape left is interface landscape right, where the app turns.
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 1)
        }
        let close = app.buttons["player.close"]
        if !close.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 5), "no controls after a tap:\n\(app.debugDescription)")
    }

    func testWelcomeSignsInToTheDemo() {
        // An empty IPTV_SERVER starts without an account: the welcome screen.
        let app = launchDemo(["IPTV_SERVER": ""])
        let iptv = app.buttons["welcome.iptv"]
        XCTAssertTrue(iptv.waitForExistence(timeout: 10), "no welcome screen:\n\(app.debugDescription)")
        shot("welcome", app)
        iptv.tap()
        let demo = app.buttons["signin.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5), "no IPTV form:\n\(app.debugDescription)")
        demo.tap()
        XCTAssertTrue(tab(app, "Live TV").waitForExistence(timeout: 20), "the demo sign-in did not open the tabs:\n\(app.debugDescription)")
    }

    func testLiveRowPlaysAndClosesWithSwipe() {
        let app = launchDemo()
        tab(app, "Live TV").tap()
        let row = app.buttons["channel.101"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no channel row:\n\(app.debugDescription)")
        row.tap()
        XCTAssertTrue(waitForState(app, "playing"), "the channel did not play")
        shot("live player", app)
        showControls(app)
        // A drag in the app's coordinates: swipeDown follows the device's portrait axes while the
        // player has turned an iPhone to landscape.
        let window = surface(app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.9)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(wait(8) { !app.descendants(matching: .any)["player.state"].exists },
                      "swipe down did not close the player; plays: \(mcp("now_playing").prefix(300)); log: \(mcp("get_log", #"{"level":"info","query":"channel","limit":6}"#).suffix(600))")
        XCTAssertTrue(wait(5) { self.mcp("now_playing").contains("\"playing\":false") || self.mcp("now_playing").contains("\\\"playing\\\" : false") },
                      "playback goes on after closing: \(mcp("now_playing"))")
    }

    func testClosingThePlayerFollowsTheDevice() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the player turns only an iPhone") }
        // Held in landscape: the screens after the player stay in landscape.
        var app = launchDemo(["IPTV_AUTOPLAY": "live:101"])
        XCTAssertTrue(waitForState(app, "playing"), "the channel did not play")
        XCUIDevice.shared.orientation = .landscapeLeft
        _ = mcp("stop_playback")
        XCTAssertTrue(wait(8) { !app.descendants(matching: .any)["player.state"].exists }, "the player did not close")
        XCTAssertTrue(wait(5) { self.isLandscape(app) }, "held in landscape, the app turned to portrait after the player")
        // Held upright: back to portrait.
        app = launchDemo(["IPTV_AUTOPLAY": "live:101"])
        XCTAssertTrue(waitForState(app, "playing"), "the channel did not play")
        XCTAssertTrue(wait(5) { self.isLandscape(app) }, "the player did not turn to landscape")
        _ = mcp("stop_playback")
        XCTAssertTrue(wait(8) { !app.descendants(matching: .any)["player.state"].exists }, "the player did not close")
        XCTAssertTrue(wait(5) { !self.isLandscape(app) }, "held upright, the app stayed in landscape after the player")
    }

    private func isLandscape(_ app: XCUIApplication) -> Bool {
        let frame = app.windows.firstMatch.frame
        return frame.width > frame.height
    }

    func testTimelineGoesBackAndLiveReturns() {
        let app = launchDemo(["IPTV_AUTOPLAY": "live:101", "IPTV_KEEPCONTROLS": "1"])
        XCTAssertTrue(waitForState(app, "playing"), "the channel did not play")
        // Some buffer first, so the timeline has room to go back.
        Thread.sleep(forTimeInterval: 15)
        showControls(app)
        let slider = app.sliders["player.timeline"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "no timeline:\n\(app.debugDescription)")
        slider.adjust(toNormalizedSliderPosition: 0.3)
        let behind = app.staticTexts["player.behind"]
        XCTAssertTrue(behind.waitForExistence(timeout: 8), "dragging the timeline back did not leave live:\n\(app.debugDescription)")
        shot("behind live", app)
        app.buttons["player.live"].tap()
        XCTAssertTrue(wait(8) { !behind.exists }, "LIVE did not return to live")
    }

    func testChannelPanelZaps() {
        let app = launchDemo(["IPTV_AUTOPLAY": "live:101", "IPTV_KEEPCONTROLS": "1"])
        XCTAssertTrue(waitForState(app, "playing"), "the channel did not play")
        showControls(app)
        let frames = ["player.close", "player.tracks", "player.pip", "player.channels"].map { "\($0): \(app.buttons[$0].exists ? "\(app.buttons[$0].frame) hittable \(app.buttons[$0].isHittable)" : "-")" }.joined(separator: "; ")
        app.buttons["player.channels"].tap()
        Thread.sleep(forTimeInterval: 1)
        shot("after tapping channels", app)
        let other = app.descendants(matching: .any)["strip.102"]
        XCTAssertTrue(other.waitForExistence(timeout: 8), "no channel panel; frames: \(frames)")
        shot("channel panel", app)
        other.tap()
        XCTAssertTrue(wait(10) { self.mcp("now_playing").contains("live:102") }, "the panel did not tune channel 102: \(mcp("now_playing"))")
        XCTAssertTrue(waitForState(app, "playing"), "channel 102 did not play")
    }

    func testSwipeLeftZapsToTheNextChannel() {
        let app = launchDemo(["IPTV_AUTOPLAY": "live:101"])
        XCTAssertTrue(waitForState(app, "playing"), "the channel did not play")
        showControls(app)
        // Zapping works with the controls hidden (they hide after 4 s).
        XCTAssertTrue(wait(8) { !app.buttons["player.close"].exists }, "the controls did not hide")
        let window = surface(app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(wait(10) { self.mcp("now_playing").contains("live:102") }, "swiping left did not tune channel 102: \(mcp("now_playing"))")
    }

    func testFilmPagePlays() {
        let app = launchDemo()
        tab(app, "Movies", "Filme").tap()
        let poster = app.buttons["movie.500"]
        XCTAssertTrue(poster.waitForExistence(timeout: 20), "no film poster:\n\(app.debugDescription)")
        poster.tap()
        let play = app.buttons["film.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "no film page:\n\(app.debugDescription)")
        shot("film page", app)
        play.tap()
        XCTAssertTrue(waitForState(app, "playing"), "the film did not play")
        showControls(app)
        XCTAssertTrue(app.staticTexts["vod.remaining"].exists, "no time left in the film player")
        app.buttons["player.close"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 8), "close did not return to the film page")
    }

    func testSearchFindsAFilm() {
        let app = launchDemo()
        tab(app, "Search", "Suchen").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field:\n\(app.debugDescription)")
        field.tap()
        field.typeText("stard")
        XCTAssertTrue(app.buttons["search.vod.m500"].waitForExistence(timeout: 10), "the search did not find Stardust:\n\(app.debugDescription)")
        shot("search", app)
    }

    /// What gestures are drawn on: on iPhone the window, whose axes follow the player's
    /// landscape; on iPad the app (its first window is not always the player's).
    private func surface(_ app: XCUIApplication) -> XCUIElement {
        UIDevice.current.userInterfaceIdiom == .phone ? app.windows.firstMatch : app
    }

    private func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }
}
