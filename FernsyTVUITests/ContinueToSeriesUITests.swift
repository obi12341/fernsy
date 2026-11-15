import XCTest

/// From Weiterschauen to the series (tv-continue-to-series 3.1) on the demo server: the card's
/// long-press menu opens an episode's series, Back after an episode lands on its series page, a
/// film still returns to Start, and "Von Anfang an" plays from the start.
final class ContinueToSeriesUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared
    /// S1 F2 of series 800 partly watched, its series known (IPTV_TESTRESUME's fourth field).
    private static let episodeEnv = ["IPTV_TESTRESUME": "episode.00101:300:2760:800"]

    /// Start with the episode in Weiterschauen and focus on its card.
    private func startWithEpisode() -> (XCUIApplication, XCUIElement) {
        let app = launchDemo(Self.episodeEnv)
        let card = app.buttons["start.resume.episode.00101"]
        focus(card, in: app, moves: [.down])
        return (app, card)
    }

    /// Long-presses the focused card and picks the menu entry with `symbol`.
    private func pick(_ symbol: String, _ app: XCUIApplication) {
        remote.press(.select, forDuration: 1.5)
        let entry = app.cells.containing(.any, identifier: symbol).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "no “\(symbol)” in the menu:\n\(app.debugDescription)")
        for _ in 0..<6 where !entry.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(entry.hasFocus, "“\(symbol)” has no focus:\n\(app.debugDescription)")
        remote.press(.select)
        XCTAssertTrue(wait(5) { !entry.exists }, "the menu stayed open")
    }

    /// `position_seconds` of the debug tool `now_playing`.
    private func playingPosition() -> Int? {
        let text = mcpCall("now_playing").replacingOccurrences(of: "\\\"", with: "\"")
        guard let match = text.range(of: #""position_seconds"\s*:\s*\d+"#, options: .regularExpression) else { return nil }
        return Int(text[match].split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
    }

    /// The menu in German, for the user (tv-continue-to-series 3.3).
    func testMenuInGerman() {
        let app = launchDemo(Self.episodeEnv, arguments: ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"])
        let card = app.buttons["start.resume.episode.00101"]
        focus(card, in: app, moves: [.down])
        remote.press(.select, forDuration: 1.5)
        let series = app.cells.containing(NSPredicate(format: "label == %@", "Zur Serie")).firstMatch
        XCTAssertTrue(series.waitForExistence(timeout: 5), "no German “Zur Serie”:\n\(app.debugDescription)")
        XCTAssertTrue(app.cells.containing(NSPredicate(format: "label == %@", "Von Anfang an")).firstMatch.exists, "no German “Von Anfang an”")
        Thread.sleep(forTimeInterval: 1)
        shot("menu-de", app)
        remote.press(.menu)
    }

    /// (a) "Zur Serie" opens the series page; Back returns to Start.
    func testMenuOpensTheSeries() {
        let (app, _) = startWithEpisode()
        remote.press(.select, forDuration: 1.5)
        XCTAssertTrue(app.cells.containing(.any, identifier: "backward.end.fill").firstMatch.waitForExistence(timeout: 5),
                      "a started episode offers no “Von Anfang an”:\n\(app.debugDescription)")
        shot("menu-episode", app)
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        pick("rectangle.stack", app)
        XCTAssertTrue(app.buttons["series.next"].waitForExistence(timeout: 15), "“Zur Serie” did not open the series:\n\(app.debugDescription)")
        remote.press(.menu)
        XCTAssertTrue(wait(10) { !app.buttons["series.next"].exists && app.buttons["start.resume.episode.00101"].exists },
                      "Back did not return to Start:\n\(app.debugDescription)")
    }

    /// (b) After the episode (started over from the menu: the demo server's clips are 52 s, a
    /// resume position minutes in would end at once), Back lands on its series page, and Back
    /// again on Start.
    func testBackAfterAnEpisodeShowsTheSeries() {
        let (app, _) = startWithEpisode()
        pick("backward.end.fill", app)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the episode does not play")
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not take focus")
        XCTAssertTrue(closePlayer(app), "the player did not close")
        XCTAssertTrue(app.buttons["series.next"].waitForExistence(timeout: 15), "closing the player did not show the series:\n\(app.debugDescription)")
        shot("series-after-episode", app)
        remote.press(.menu)
        XCTAssertTrue(wait(10) { !app.buttons["series.next"].exists && app.buttons["start.hero.resume"].exists },
                      "Back from the series did not return to Start:\n\(app.debugDescription)")
    }

    /// (c) A film from Weiterschauen returns to Start; (d) "Von Anfang an" plays it from 0.
    func testFilmStartsOverAndReturnsToStart() {
        let app = launchDemo(["IPTV_TESTRESUME": "movie.500:1200:3600"])
        let card = app.buttons["start.resume.movie.500"]
        focus(card, in: app, moves: [.down])
        pick("backward.end.fill", app)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the film does not play from the start")
        let position = playingPosition() ?? 99
        XCTAssertLessThan(position, 15, "“Von Anfang an” did not start at 0 (position \(position) s)")
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not take focus")
        XCTAssertTrue(closePlayer(app), "the player did not close")
        // Started over and stopped under 30 s: the film leaves Weiterschauen, Start stays.
        XCTAssertTrue(wait(10) { app.buttons["start.hero.resume"].exists && !app.buttons["series.next"].exists },
                      "a film did not return to Start:\n\(app.debugDescription)")
    }

    /// The test Jellyfin's fixture user (scripts/jellyfin-test-server.sh): token and user id.
    private func jellyfinLogin() -> (token: String, user: String)? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8097/Users/AuthenticateByName")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(#"MediaBrowser Client="uitest", Device="uitest", DeviceId="fernsy-uitest", Version="1""#, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"Username":"fixture","Pw":"fixture-pass"}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        var result: (String, String)?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["AccessToken"] as? String, let user = (json["User"] as? [String: Any])?["Id"] as? String {
                result = (token, user)
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        return result
    }

    /// Clears an item's position on the test Jellyfin, so the fixture stays as other tests expect it.
    private func clearJellyfinPosition(_ itemId: String) { setJellyfinPosition(itemId, seconds: 0) }

    /// Sets an item's position on the test Jellyfin (not watched).
    private func setJellyfinPosition(_ itemId: String, seconds: Int) {
        guard let login = jellyfinLogin() else { return }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8097/UserItems/\(itemId)/UserData?userId=\(login.user)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(#"MediaBrowser Client="uitest", Device="uitest", DeviceId="fernsy-uitest", Version="1", Token="\#(login.token)""#, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"PlaybackPositionTicks":\#(seconds * 10_000_000),"Played":false}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 10)
    }

    /// Jellyfin (tv-continue-to-series 3.2), with the local test Jellyfin (skipped without it):
    /// "Nächste Folge" on Übersicht offers "Abspielen" and "Zur Serie" without "Von Anfang an";
    /// after playing, Back lands on the series page and then Übersicht; the episode, now started,
    /// is in Start's "Weiterschauen", whose "Zur Serie" opens the Jellyfin series.
    func testJellyfinEpisodeLeadsToItsSeries() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let app = launchDemo(["IPTV_SERVER": "", "JF_SERVER": "http://127.0.0.1:8097", "JF_USER": "fixture", "JF_PASS": "fixture-pass"])
        showTab("Jellyfin", app)
        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jellyfin.next.'")).firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["jellyfin.state"].waitForExistence(timeout: 30), "no Jellyfin tab")
        // Übersicht builds its rows as they come near: down until Next Up is there.
        for _ in 0..<6 where !next.waitForExistence(timeout: 2) { pressAndWaitForFocusMove(.down, app) }
        XCTAssertTrue(next.exists, "no Next Up on Übersicht:\n\(app.debugDescription)")
        let itemId = String(next.identifier.dropFirst("jellyfin.next.".count))
        addTeardownBlock { self.clearJellyfinPosition(itemId) }
        focus(app.buttons["jellyfin.next.\(itemId)"], in: app, moves: [.down])

        remote.press(.select, forDuration: 1.5)
        XCTAssertTrue(app.cells.containing(.any, identifier: "rectangle.stack").firstMatch.waitForExistence(timeout: 5),
                      "no “Zur Serie” for a Next Up episode:\n\(app.debugDescription)")
        XCTAssertFalse(app.cells.containing(.any, identifier: "backward.end.fill").firstMatch.exists, "“Von Anfang an” on an episode not started")
        shot("menu-next-up", app)
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        pick("play.fill", app)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the episode does not play")
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not take focus")
        // 40 s in (of 2 min), so the server lists it under Continue Watching afterwards. The series
        // page is recognised by its favourite star: "Nächste Episode" depends on the server's state.
        _ = mcpCall("seek", #"{"by_seconds":40}"#)
        Thread.sleep(forTimeInterval: 4)
        XCTAssertTrue(closePlayer(app), "the player did not close")
        XCTAssertTrue(app.buttons["series.favorite"].waitForExistence(timeout: 15), "closing the player did not show the series:\n\(app.debugDescription)")
        remote.press(.menu)
        XCTAssertTrue(wait(10) { !app.buttons["series.favorite"].exists && app.descendants(matching: .any)["jellyfin.state"].exists },
                      "Back from the series did not return to Übersicht:\n\(app.debugDescription)")

        // Jellyfin keeps no resume position for items under 5 minutes (MinResumeDuration) and marks
        // the 2-minute fixture episode watched on stop: the position for Weiterschauen is set on
        // the server, and leaving the app and coming back makes it ask Jellyfin again.
        setJellyfinPosition(itemId, seconds: 60)
        remote.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()
        XCTAssertTrue(waitForLog("back in the front", timeout: 20), "coming back was not noticed")
        showTab("Start", app)
        let resume = app.buttons["start.resume.jf.\(itemId)"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30), "the episode is not in Weiterschauen:\n\(app.debugDescription)")
        focus(resume, in: app, moves: [.down, .right])
        pick("rectangle.stack", app)
        XCTAssertTrue(app.buttons["series.favorite"].waitForExistence(timeout: 15), "“Zur Serie” did not open the Jellyfin series:\n\(app.debugDescription)")
        shot("jellyfin-series-from-start", app)
    }
}
