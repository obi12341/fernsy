import XCTest

/// Continue Watching follows the other devices (continue-watching-fresh 3.5), on the demo server
/// with a stand-in for iCloud (IPTV_TESTSYNC): positions are put in "from another device" by the
/// debug tool `sync_from_other_device`, which tells the app nothing, as when iCloud's notification
/// does not come; leaving the app and coming back has to bring them.
final class ContinueWatchingSyncUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func entry(_ key: String, _ app: XCUIApplication) -> XCUIElement { app.buttons["start.resume.\(key)"] }

    private func put(_ positions: String) {
        let answer = mcpCall("sync_from_other_device", #"{"positions": \#(positions)}"#)
        XCTAssertTrue(answer.contains("\"put\""), "the tool did not put the positions: \(answer)")
    }

    /// Home, then back into the app; waits until the app logged that it is back in the front.
    /// (The app's `state` does not change on Home in the simulator, so the log is the signal.)
    private func leaveAndComeBack(_ app: XCUIApplication) {
        let before = appLog("back in the front").count
        remote.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()
        XCTAssertTrue(wait(20) { self.appLog("back in the front").count > before }, "coming back was not noticed")
    }

    private func heroShows(_ title: String, _ app: XCUIApplication) -> Bool {
        let resume = app.buttons["start.hero.resume"]
        return resume.exists && resume.label.hasPrefix("Resume") && app.staticTexts[title].exists
    }

    /// (a) and (b): a film and an episode of a series never opened here, continued "on the Mac",
    /// show after coming back, without a tab change.
    func testComingBackShowsWhatWasWatchedElsewhere() {
        let app = launchDemo(["IPTV_TESTSYNC": "memory"])
        XCTAssertTrue(waitForLog(" films, ", timeout: 40), "the catalog did not load")
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 15), "no large entry:\n\(app.debugDescription)")

        put(#"[{"key": "movie.500", "position": 30, "duration": 52}]"#)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(entry("movie.500", app).exists, "the position arrived without asking again")

        leaveAndComeBack(app)
        XCTAssertTrue(entry("movie.500", app).waitForExistence(timeout: 15), "the film is not in Continue Watching:\n\(app.debugDescription)")
        XCTAssertTrue(wait(10) { self.heroShows("Stardust", app) }, "the large entry does not show the film:\n\(app.debugDescription)")
        shot("film-from-other-device", app)

        // An episode of a series whose page was never opened here, newer than the film.
        put(#"[{"key": "episode.00101", "position": 300, "duration": 2760, "series": 800}]"#)
        leaveAndComeBack(app)
        // From the provider, or from the device when an earlier run kept the list.
        XCTAssertTrue(waitForLog("Start: episodes of series 800 from", timeout: 20), "the series was not loaded")
        XCTAssertTrue(entry("episode.00101", app).waitForExistence(timeout: 15), "the episode is not in Continue Watching:\n\(app.debugDescription)")
        XCTAssertTrue(wait(10) { self.heroShows("Harbour Detectives", app) }, "the large entry does not show the episode:\n\(app.debugDescription)")
        shot("episode-from-other-device", app)

        // Asked again: the list is known, no second request.
        let requests = appLog("episodes of series 800 loaded").count
        leaveAndComeBack(app)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(appLog("episodes of series 800 loaded").count, requests, "the series was requested again")
    }

    /// (c): after a relaunch the episode is listed from the kept list, before the provider answers.
    func testAfterARelaunchFromTheKeptList() {
        var app = launchDemo(["IPTV_TESTSYNC": "memory"])
        XCTAssertTrue(waitForLog(" films, ", timeout: 40), "the catalog did not load")
        put(#"[{"key": "episode.00101", "position": 300, "duration": 2760, "series": 800}]"#)
        leaveAndComeBack(app)
        XCTAssertTrue(entry("episode.00101", app).waitForExistence(timeout: 20), "the episode is not in Continue Watching")
        app.terminate()

        app = launchDemo(["IPTV_TESTSYNC": "memory-keep"])
        XCTAssertTrue(waitForLog("Start: episodes of series 800 from the device", timeout: 40), "the kept list was not used:\n\(app.debugDescription)")
        XCTAssertTrue(entry("episode.00101", app).waitForExistence(timeout: 15), "the episode is not listed after the relaunch")
        XCTAssertTrue(appLog("episodes of series 800 loaded").isEmpty, "the provider was asked although the list was kept")
    }

    /// (d): a position from an older version (no series) is not listed until the series' list is
    /// loaded here; then it is, and its series goes to the other devices.
    func testAnOldPositionGetsItsSeries() {
        var app = launchDemo(["IPTV_TESTSYNC": "memory"])
        XCTAssertTrue(waitForLog(" films, ", timeout: 40), "the catalog did not load")
        put(#"[{"key": "episode.00102", "position": 300, "duration": 2820}]"#)
        leaveAndComeBack(app)
        Thread.sleep(forTimeInterval: 4)
        XCTAssertFalse(entry("episode.00102", app).exists, "listed without its series")
        app.terminate()

        // Again with what this device has, opening a link to an episode of the series (as from
        // the Top Shelf): its page loads the list, and the old position gets its series.
        // (A link opened in a running app relaunches it in the simulator.)
        app = launchDemo(["IPTV_TESTSYNC": "memory-keep", "IPTV_OPEN": "fernsy-dev://open?item=episode:800:00100"])
        XCTAssertTrue(waitForLog("episodes of series 800 loaded", timeout: 40), "the series was not loaded")
        XCTAssertTrue(app.buttons["series.next"].waitForExistence(timeout: 10), "the series' page did not open")
        XCTAssertTrue(waitForLog("iCloud: sent the series of", timeout: 10), "the series was not sent")
        app.terminate()

        // The next launch lists it on Start, from the kept list.
        app = launchDemo(["IPTV_TESTSYNC": "memory-keep"])
        XCTAssertTrue(entry("episode.00102", app).waitForExistence(timeout: 40), "the old position is not listed after its series loaded:\n\(app.debugDescription)")
    }

    // MARK: Jellyfin (3.7)

    /// The test Jellyfin's user, a token and its film (scripts/jellyfin-test-server.sh).
    private func jellyfinFixture() throws -> (token: String, user: String, film: String) {
        func call(_ path: String, method: String = "GET", token: String? = nil, body: String? = nil) throws -> Data {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8097" + path)!)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token.map { #"MediaBrowser Token="\#($0)""# }
                             ?? #"MediaBrowser Client="uitest", Device="uitest", DeviceId="fernsy-uitest-cwf", Version="1""#, forHTTPHeaderField: "Authorization")
            request.httpBody = body.map { Data($0.utf8) }
            let done = DispatchSemaphore(value: 0)
            var result = Data()
            URLSession.shared.dataTask(with: request) { data, _, _ in result = data ?? Data(); done.signal() }.resume()
            _ = done.wait(timeout: .now() + 10)
            return result
        }
        let auth = try JSONSerialization.jsonObject(with: try call("/Users/AuthenticateByName", method: "POST", body: #"{"Username":"fixture","Pw":"fixture-pass"}"#)) as? [String: Any]
        let token = try XCTUnwrap(auth?["AccessToken"] as? String)
        let user = try XCTUnwrap((auth?["User"] as? [String: Any])?["Id"] as? String)
        let items = try JSONSerialization.jsonObject(with: try call("/Items?Recursive=true&IncludeItemTypes=Movie&userId=\(user)", token: token)) as? [String: Any]
        let film = try XCTUnwrap(((items?["Items"] as? [[String: Any]])?.first)?["Id"] as? String)
        let item = try JSONSerialization.jsonObject(with: try call("/Items/\(film)?userId=\(user)", token: token)) as? [String: Any]
        previousTicks = ((item?["UserData"] as? [String: Any])?["PlaybackPositionTicks"] as? NSNumber)?.int64Value ?? 0
        setPosition = { ticks in _ = try? call("/UserItems/\(film)/UserData?userId=\(user)", method: "POST", token: token, body: #"{"PlaybackPositionTicks": \#(ticks)}"#) }
        signOut = { _ = try? call("/Sessions/Logout", method: "POST", token: token) }
        return (token, user, film)
    }
    private var setPosition: (Int64) -> Void = { _ in }
    private var signOut: () -> Void = {}
    /// The film's position before the test: other tests rely on the position a run leaves.
    private var previousTicks: Int64 = 0

    /// Continued in another Jellyfin client while the app was left: Continue Watching shows it
    /// after coming back; a second return within a minute does not ask the server again.
    func testJellyfinRowsFollowTheServer() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let fixture = try jellyfinFixture()
        setPosition(0)
        let previous = previousTicks
        addTeardownBlock { self.setPosition(previous); self.signOut() }
        let app = launchDemo(["IPTV_SERVER": "", "JF_SERVER": "http://127.0.0.1:8097", "JF_USER": "fixture", "JF_PASS": "fixture-pass"])
        let film = entry("jf.\(fixture.film)", app)
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 40), "Start did not load:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(film.exists, "the film is listed before it was continued")

        setPosition(1_800_000_000)  // 3 minutes
        leaveAndComeBack(app)
        XCTAssertTrue(film.waitForExistence(timeout: 20), "the film is not in Continue Watching:\n\(app.debugDescription)")
        XCTAssertTrue(wait(10) { self.heroShows("Fixture Film (2024)", app) }, "the large entry does not show the film")
        shot("jellyfin-from-other-client", app)

        let asked = appLog("Start's rows loaded again").count
        leaveAndComeBack(app)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(appLog("Start's rows loaded again").count, asked, "the server was asked again within a minute")
    }
}
