import XCTest

/// Subtitles drawn over the picture (fix/subtitles-ios-tv): the Apple TV listed and switched
/// subtitle tracks but drew none. With the local test Jellyfin (scripts/jellyfin-test-server.sh,
/// skipped without it), whose film has an English subtitle file: choosing it in the subtitle
/// panel shows its text, "Off" removes it.
final class SubtitleOverlayUITests: FernsyUITestCase {
    func testChosenSubtitleIsShown() throws {
        try XCTSkipUnless(jellyfinRunning(), "the local test Jellyfin is not running")
        let film = try XCTUnwrap(jellyfinFilmId(), "the test Jellyfin has no film")
        let app = launchDemo(["IPTV_SERVER": "", "JF_SERVER": "http://127.0.0.1:8097", "JF_USER": "fixture", "JF_PASS": "fixture-pass"])
        let remote = XCUIRemote.shared
        let state = app.descendants(matching: .any)["player.state"]
        // The fixture film resumes at 2:30 in other tests: put back after playing.
        addTeardownBlock { self.setFilmPosition(film, seconds: 150) }
        // play_item fails until Jellyfin has signed in.
        XCTAssertTrue(wait(30) { !self.mcpCall("play_item", #"{"item_id":"jellyfin:\#(film)","from_start":true}"#).contains(#""isError":true"#) },
                      "the film cannot be played")
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the film does not play")
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not take focus:\n\(app.debugDescription)")
        let subtitle = app.staticTexts["player.subtitle"]

        // Down opens the subtitle panel; the film's English track turns subtitles on.
        remote.press(.down)
        let english = app.buttons.matching(NSPredicate(format: "label CONTAINS 'English'")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5), "no English track in the panel:\n\(app.debugDescription)")
        XCTAssertTrue(move(to: english, with: .down), "the English track cannot be focused:\n\(app.debugDescription)")
        remote.press(.select)
        XCTAssertTrue(subtitle.waitForExistence(timeout: 10), "the chosen subtitle is not shown:\n\(app.debugDescription)")
        XCTAssertTrue(subtitle.label.hasPrefix("Fixture subtitle"), "unexpected subtitle text: \(subtitle.label)")
        XCTAssertTrue(app.frame.contains(subtitle.frame), "the subtitle is off screen: \(subtitle.frame)")
        shot("subtitle-shown", app)

        // "Off" removes it again.
        XCTAssertTrue(waitForPlayerFocus(app), "the player did not get focus back")
        remote.press(.down)
        let off = app.buttons["Off"]
        XCTAssertTrue(off.waitForExistence(timeout: 5), "no Off in the panel:\n\(app.debugDescription)")
        XCTAssertTrue(move(to: off, with: .up), "Off cannot be focused:\n\(app.debugDescription)")
        remote.press(.select)
        XCTAssertTrue(wait(5) { !subtitle.exists }, "the subtitle stays after Off")
        XCTAssertTrue(closePlayer(app), "the player did not close")
        Thread.sleep(forTimeInterval: 2)
    }

    /// Presses `button` until `element` has focus, waiting for the focus after each press: one
    /// press too many past the top of the panel leaves it (and opens the audio panel).
    private func move(to element: XCUIElement, with button: XCUIRemote.Button) -> Bool {
        if wait(1, { element.hasFocus }) { return true }
        for _ in 0..<4 {
            XCUIRemote.shared.press(button)
            if wait(2, { element.hasFocus }) { return true }
        }
        return false
    }

    /// The fixture film's id on the test Jellyfin.
    private func jellyfinFilmId() -> String? {
        jellyfin { call, user, token in
            let items = call("/Items?Recursive=true&IncludeItemTypes=Movie&userId=\(user)", "GET", token, nil)
            return ((items?["Items"] as? [[String: Any]])?.first)?["Id"] as? String
        }
    }

    private func setFilmPosition(_ film: String, seconds: Int) {
        _ = jellyfin { call, user, token in
            call("/UserItems/\(film)/UserData?userId=\(user)", "POST", token, #"{"PlaybackPositionTicks":\#(seconds * 10_000_000),"Played":false}"#)
        }
    }

    /// Signs in to the test Jellyfin, runs `body` with its API and signs out.
    private func jellyfin<T>(_ body: (_ call: (String, String, String?, String?) -> [String: Any]?, _ user: String, _ token: String) -> T?) -> T? {
        func call(_ path: String, method: String = "GET", token: String? = nil, body: String? = nil) -> [String: Any]? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8097" + path)!)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let client = #"MediaBrowser Client="uitest", Device="uitest", DeviceId="fernsy-uitest-sub", Version="1""#
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
