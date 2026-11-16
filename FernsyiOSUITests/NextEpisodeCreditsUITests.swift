import XCTest

/// The next episode at the credits and Skip Intro on iPhone and iPad (jellyfin-media-segments)
/// with the local test Jellyfin (scripts/jellyfin-test-server.sh, skipped without it).
/// `JF_TESTSEGMENTS` stands in for a segment provider; the fixture's watched state is put back.
final class NextEpisodeCreditsUITests: XCTestCase {
    private static let segments = "intro:5-20,outro:96-120"
    private var episodes: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(jellyfin { _, _, _ in true } == true, "the local test Jellyfin is not running")
        episodes = jellyfin { call, user, token in
            let items = call("/Items?Recursive=true&IncludeItemTypes=Episode&SortBy=IndexNumber&userId=\(user)", "GET", token, nil)
            return (items?["Items"] as? [[String: Any]])?.compactMap { $0["Id"] as? String }
        } ?? []
        XCTAssertEqual(episodes.count, 3, "the test Jellyfin has no Fixture Show with three episodes")
        let ids = episodes
        addTeardownBlock {
            // S01E01–02 watched, S01E03 next, no positions.
            _ = self.jellyfin { call, user, token -> Bool? in
                for (index, id) in ids.enumerated() {
                    _ = call("/UserItems/\(id)/UserData?userId=\(user)", "POST", token, #"{"PlaybackPositionTicks":0,"Played":\#(index < 2)}"#)
                }
                return true
            }
        }
    }

    /// Skip Intro shows with hidden controls and skips; the card comes at the credits and starts
    /// the next episode.
    func testSkipIntroAndNextEpisodeAtTheCredits() throws {
        let app = launch()
        play(episodes[0], app)
        let close = app.buttons["player.close"]
        XCTAssertTrue(wait(10) { !close.exists }, "the controls do not hide")
        let skip = app.buttons["player.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "no Skip Intro with hidden controls:\n\(app.debugDescription)")
        shot("skip-intro", app)
        skip.tap()
        XCTAssertTrue(wait(8) { (self.nowPlaying()?["position_seconds"] as? Int ?? 0) >= 20 }, "Skip Intro did not skip")

        XCTAssertTrue(seek(to: 93), "cannot seek")
        let card = app.descendants(matching: .any)["next.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 12), "no next-episode card at the credits:\n\(app.debugDescription)")
        XCTAssertEqual(app.descendants(matching: .any)["vod.countdown"].value as? String, "counting", "the card does not count down")
        shot("card-at-credits", app)
        XCTAssertTrue(wait(20) { self.nowPlaying()?["item_id"] as? String == "jellyfin:\(self.episodes[1])" }, "the countdown did not start S01E02")
        // The controls hid while the card showed: a tap on the picture brings them back.
        if !close.waitForExistence(timeout: 2) { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 5), "no controls to close the player")
        close.tap()
        Thread.sleep(forTimeInterval: 1)
    }

    /// Watch Credits closes the card; the episode plays to its end with no card again.
    func testWatchCreditsPlaysToTheEnd() throws {
        let app = launch()
        play(episodes[1], app)
        XCTAssertTrue(seek(to: 93), "cannot seek")
        let card = app.descendants(matching: .any)["next.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 12), "no next-episode card at the credits:\n\(app.debugDescription)")
        app.buttons["next.dismiss"].tap()
        XCTAssertTrue(wait(3) { !card.exists }, "Watch Credits did not close the card")
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertEqual(state.value as? String, "playing", "Watch Credits stopped the episode")
        XCTAssertTrue(seek(to: 115), "cannot seek")
        XCTAssertTrue(wait(15) { state.value as? String == "ended" }, "the episode did not play to its end")
        XCTAssertFalse(wait(4) { card.exists }, "the card came back at the end")
    }

    // MARK: Helpers

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "",
            "JF_SERVER": "http://127.0.0.1:8097",
            "JF_USER": "fixture",
            "JF_PASS": "fixture-pass",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
            "JF_TESTSEGMENTS": Self.segments,
        ]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    private func play(_ id: String, _ app: XCUIApplication) {
        // play_item fails until Jellyfin has signed in.
        XCTAssertTrue(wait(30) { !self.mcp("play_item", #"{"item_id":"jellyfin:\#(id)","from_start":true}"#).contains(#""isError":true"#) },
                      "the episode cannot be played")
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.exists && state.value as? String == "playing" }, "the episode does not play")
    }

    private func nowPlaying() -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(mcp("now_playing").utf8)) as? [String: Any],
              let result = json["result"] as? [String: Any] else { return nil }
        return result["structuredContent"] as? [String: Any]
    }

    /// The debug server seeks only relatively.
    private func seek(to target: Int) -> Bool {
        guard let now = nowPlaying()?["position_seconds"] as? Int else { return false }
        return mcp("seek", #"{"by_seconds":\#(target - now)}"#).contains("position_seconds")
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Signs in to the test Jellyfin, runs `body` with its API and signs out; nil when it does not answer.
    private func jellyfin<T>(_ body: (_ call: (String, String, String?, String?) -> [String: Any]?, _ user: String, _ token: String) -> T?) -> T? {
        func call(_ path: String, method: String = "GET", token: String? = nil, body: String? = nil) -> [String: Any]? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8097" + path)!)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let client = #"MediaBrowser Client="uitest", Device="uitest", DeviceId="fernsy-uitest-next-ios", Version="1""#
            request.setValue(token.map { client + #", Token="\#($0)""# } ?? client, forHTTPHeaderField: "Authorization")
            request.httpBody = body.map { Data($0.utf8) }
            let done = DispatchSemaphore(value: 0)
            var result: [String: Any]?
            URLSession.shared.dataTask(with: request) { data, _, _ in
                result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                done.signal()
            }.resume()
            _ = done.wait(timeout: .now() + 10)
            return result
        }
        guard let auth = call("/Users/AuthenticateByName", method: "POST", body: #"{"Username":"fixture","Pw":"fixture-pass"}"#),
              let token = auth["AccessToken"] as? String, let user = (auth["User"] as? [String: Any])?["Id"] as? String else { return nil }
        defer { _ = call("/Sessions/Logout", method: "POST", token: token) }
        return body({ call($0, method: $1, token: $2, body: $3) }, user, token)
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

    private func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }
}
