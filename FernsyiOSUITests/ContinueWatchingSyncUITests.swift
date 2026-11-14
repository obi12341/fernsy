import XCTest

/// Continue Watching follows the other devices on iPhone and iPad (continue-watching-fresh 3.6),
/// on the demo server with a stand-in for iCloud (IPTV_TESTSYNC): positions are put in "from
/// another device" by the debug tool `sync_from_other_device`, which tells the app nothing;
/// leaving the app and coming back has to bring them.
final class ContinueWatchingSyncUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1", "IPTV_MCP": "1", "IPTV_MCPTOKEN": "test",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev", "IPTV_USER": "demo", "IPTV_PASS": "demo",
        ].merging(env) { $1 }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    private func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return condition()
    }

    /// A tool of the app's debug MCP server (port 52326).
    @discardableResult
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

    private func logCount(_ query: String) -> Int {
        let text = mcp("get_log", #"{"level":"detail","limit":2000,"query":"\#(query)"}"#)
        return text.components(separatedBy: query).count - 1
    }

    private func put(_ positions: String) {
        XCTAssertTrue(mcp("sync_from_other_device", #"{"positions": \#(positions)}"#).contains("\\\"put\\\""), "the tool did not put the positions")
    }

    private func leaveAndComeBack(_ app: XCUIApplication) {
        let before = logCount("back in the front")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        XCTAssertTrue(wait(20) { self.logCount("back in the front") > before }, "coming back was not noticed")
    }

    private func entry(_ key: String, _ app: XCUIApplication) -> XCUIElement { app.buttons["start.resume.\(key)"].firstMatch }

    private func heroShows(_ title: String, _ app: XCUIApplication) -> Bool {
        let resume = app.buttons["start.hero.resume"].firstMatch
        return resume.exists && resume.label.hasPrefix("Resume") && app.staticTexts[title].exists
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A film and an episode of a series never opened here, continued "on the Mac", show after
    /// coming back, without a tab change; at the next launch without a connection the episode is
    /// still listed, from the kept list.
    func testComingBackShowsWhatWasWatchedElsewhere() {
        var app = launch(["IPTV_TESTSYNC": "memory"])
        XCTAssertTrue(wait(40) { self.logCount(" films, ") > 0 }, "the catalog did not load")
        XCTAssertTrue(app.buttons["start.hero.resume"].firstMatch.waitForExistence(timeout: 15), "no large entry:\n\(app.debugDescription)")

        put(#"[{"key": "movie.500", "position": 30, "duration": 52}]"#)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(entry("movie.500", app).exists, "the position arrived without asking again")
        leaveAndComeBack(app)
        XCTAssertTrue(wait(15) { self.heroShows("Stardust", app) }, "the large entry does not show the film:\n\(app.debugDescription)")
        XCTAssertTrue(entry("movie.500", app).exists, "the film is not in Continue Watching")
        shot("film-from-other-device", app)

        put(#"[{"key": "episode.00101", "position": 300, "duration": 2760, "series": 800}]"#)
        leaveAndComeBack(app)
        XCTAssertTrue(wait(20) { self.heroShows("Harbour Detectives", app) }, "the large entry does not show the episode:\n\(app.debugDescription)")
        XCTAssertTrue(entry("episode.00101", app).exists, "the episode is not in Continue Watching")
        shot("episode-from-other-device", app)
        app.terminate()

        app = launch(["IPTV_TESTSYNC": "memory-keep", "IPTV_TESTOFFLINE": "1"])
        XCTAssertTrue(app.descendants(matching: .any)["offline.note"].firstMatch.waitForExistence(timeout: 30), "not offline:\n\(app.debugDescription)")
        XCTAssertTrue(wait(20) { self.logCount("Start: episodes of series 800 from the device") > 0 }, "the kept list was not used")
        XCTAssertTrue(wait(15) { self.entry("episode.00101", app).exists }, "the episode is not listed offline:\n\(app.debugDescription)")
        shot("episode-offline", app)
    }
}
