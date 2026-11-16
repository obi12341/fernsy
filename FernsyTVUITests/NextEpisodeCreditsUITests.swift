import XCTest

/// The next episode at the credits and Skip Intro (jellyfin-media-segments) with the local test
/// Jellyfin (scripts/jellyfin-test-server.sh, skipped without it): its Fixture Show has three
/// 2-minute episodes with chapters ("Credits" at 1:40). `JF_TESTSEGMENTS` stands in for a segment
/// provider. The fixture's watched state (S01E01–02 watched, S01E03 next) is put back afterwards.
final class NextEpisodeCreditsUITests: FernsyUITestCase {
    private static let segments = "intro:5-20,outro:96-120"
    private var episodes: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        episodes = jellyfinEpisodes()
        XCTAssertEqual(episodes.count, 3, "the test Jellyfin has no Fixture Show with three episodes")
        let ids = episodes
        addTeardownBlock { self.restoreFixture(ids) }
    }

    /// Select during the intro skips it; the card comes at the credits, counts down and starts the
    /// next episode; the episode left in the credits (88 %) is marked as played.
    func testSkipIntroAndNextEpisodeAtTheCredits() throws {
        let app = launch(["JF_TESTSEGMENTS": Self.segments])
        play(episodes[0], app)
        let skip = app.descendants(matching: .any)["player.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 20), "no Skip Intro during the intro:\n\(app.debugDescription)")
        shot("skip-intro", app)
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(8) { (self.position() ?? 0) >= 20 }, "Select did not skip the intro: at \(position() ?? -1) s")
        XCTAssertTrue(wait(5) { !skip.exists }, "Skip Intro stays after the intro")

        XCTAssertTrue(seek(to: 93), "cannot seek")
        let card = app.descendants(matching: .any)["next.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 12), "no next-episode card at the credits:\n\(app.debugDescription)")
        XCTAssertEqual(app.descendants(matching: .any)["vod.countdown"].value as? String, "counting", "the card does not count down")
        XCTAssertEqual(app.descendants(matching: .any)["player.state"].value as? String, "playing", "the credits do not play on")
        shot("card-at-credits", app)
        XCTAssertTrue(wait(20) { self.playingItem() == "jellyfin:\(self.episodes[1])" }, "the countdown did not start S01E02")
        XCTAssertTrue(wait(10) { self.played(self.episodes[0]) == true }, "S01E01 is not marked as played after leaving it in the credits")
        XCTAssertTrue(waitForLog("prefetched next episode", timeout: 2), "the next episode was not prefetched")
        XCTAssertTrue(closePlayer(app), "the player did not close")
    }

    /// Back on the card during the credits: the credits play to the end, and no card comes again.
    func testBackOnTheCardKeepsTheCreditsPlaying() throws {
        let app = launch(["JF_TESTSEGMENTS": Self.segments])
        play(episodes[1], app)
        XCTAssertTrue(seek(to: 93), "cannot seek")
        let card = app.descendants(matching: .any)["next.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 12), "no next-episode card at the credits:\n\(app.debugDescription)")
        XCTAssertTrue(waitForFocus(app.buttons["next.play"]), "Play Now has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(wait(3) { !card.exists }, "Back did not close the card")
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertEqual(state.value as? String, "playing", "Back stopped the episode")
        XCTAssertTrue(seek(to: 115), "cannot seek")
        XCTAssertTrue(wait(15) { state.value as? String == "ended" }, "the episode did not play to its end")
        XCTAssertFalse(wait(4) { card.exists }, "the card came back at the end")
        XCTAssertTrue(closePlayer(app), "the player did not close")
    }

    /// After one auto-started episode (limit 1 for the test) the next card asks instead of counting.
    func testStillWatchingAfterAutoStartedEpisodes() throws {
        let app = launch(["JF_TESTSEGMENTS": Self.segments, "JF_TESTSTILLWATCHING": "1"])
        play(episodes[0], app)
        XCTAssertTrue(seek(to: 93), "cannot seek")
        XCTAssertTrue(wait(30) { self.playingItem() == "jellyfin:\(self.episodes[1])" }, "the countdown did not start S01E02")
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "S01E02 does not play")
        XCTAssertTrue(seek(to: 93), "cannot seek")
        let card = app.descendants(matching: .any)["next.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 12), "no card at the credits of S01E02:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Are you still watching?"].exists, "the card does not ask:\n\(app.debugDescription)")
        XCTAssertNotEqual(app.descendants(matching: .any)["vod.countdown"].value as? String, "counting", "the card counts down")
        shot("still-watching", app)
        XCTAssertFalse(wait(13) { self.playingItem() != "jellyfin:\(self.episodes[1])" }, "the next episode started by itself")
        XCTAssertTrue(closePlayer(app), "the player did not close")
    }

    /// Without segments the "Credits" chapter at 1:40 brings the card (S01E02: S01E03 follows).
    func testCreditsChapterWithoutSegments() throws {
        let app = launch([:])
        play(episodes[1], app)
        XCTAssertTrue(seek(to: 95), "cannot seek")
        let card = app.descendants(matching: .any)["next.card"]
        XCTAssertFalse(wait(3) { card.exists }, "the card came before the chapter")
        XCTAssertTrue(card.waitForExistence(timeout: 12), "no card at the Credits chapter:\n\(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(position() ?? 0, 99, "the card came before 1:40")
        XCTAssertTrue(closePlayer(app), "the player did not close")
    }

    // MARK: Helpers

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = launchDemo(["IPTV_SERVER": "", "JF_SERVER": "http://127.0.0.1:8097", "JF_USER": "fixture", "JF_PASS": "fixture-pass"]
            .merging(extra) { $1 })
        return app
    }

    private func play(_ id: String, _ app: XCUIApplication) {
        // play_item fails until Jellyfin has signed in.
        XCTAssertTrue(wait(30) { !self.mcpCall("play_item", #"{"item_id":"jellyfin:\#(id)","from_start":true}"#).contains(#""isError":true"#) },
                      "the episode cannot be played")
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the episode does not play")
    }

    private func nowPlaying() -> [String: Any]? {
        let text = mcpCall("now_playing")
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let result = json["result"] as? [String: Any] else { return nil }
        return result["structuredContent"] as? [String: Any]
    }

    private func position() -> Int? { nowPlaying()?["position_seconds"] as? Int }

    /// The debug server seeks only relatively.
    private func seek(to target: Int) -> Bool {
        guard let now = position() else { return false }
        return mcpCall("seek", #"{"by_seconds":\#(target - now)}"#).contains("position_seconds")
    }

    private func playingItem() -> String? { nowPlaying()?["item_id"] as? String }

    private func jellyfinEpisodes() -> [String] {
        jellyfin { call, user, token in
            let items = call("/Items?Recursive=true&IncludeItemTypes=Episode&SortBy=IndexNumber&userId=\(user)", "GET", token, nil)
            return (items?["Items"] as? [[String: Any]])?.compactMap { $0["Id"] as? String }
        } ?? []
    }

    private func played(_ id: String) -> Bool? {
        jellyfin { call, user, token in
            (call("/Items/\(id)?userId=\(user)", "GET", token, nil)?["UserData"] as? [String: Any])?["Played"] as? Bool
        }
    }

    /// S01E01–02 watched, S01E03 next, no positions.
    private func restoreFixture(_ ids: [String]) {
        _ = jellyfin { call, user, token -> Bool? in
            for (index, id) in ids.enumerated() {
                _ = call("/UserItems/\(id)/UserData?userId=\(user)", "POST", token, #"{"PlaybackPositionTicks":0,"Played":\#(index < 2)}"#)
            }
            return true
        }
    }

    /// Signs in to the test Jellyfin, runs `body` with its API and signs out.
    private func jellyfin<T>(_ body: (_ call: (String, String, String?, String?) -> [String: Any]?, _ user: String, _ token: String) -> T?) -> T? {
        func call(_ path: String, method: String = "GET", token: String? = nil, body: String? = nil) -> [String: Any]? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8097" + path)!)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let client = #"MediaBrowser Client="uitest", Device="uitest", DeviceId="fernsy-uitest-next", Version="1""#
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
}
