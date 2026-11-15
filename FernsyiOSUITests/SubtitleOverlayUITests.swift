import XCTest

/// Subtitles drawn over the picture on iPhone and iPad (fix/subtitles-ios-tv): the track menu
/// switched subtitles on, but nothing was drawn. With the local test Jellyfin
/// (scripts/jellyfin-test-server.sh, skipped without it), whose film has an English subtitle
/// file: choosing it in the track menu shows its text, "Off" removes it. The menu stays open
/// past the controls' hiding time.
final class SubtitleOverlayUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testChosenSubtitleIsShown() throws {
        try XCTSkipUnless(jellyfin { _, _, _ in true } == true, "the local test Jellyfin is not running")
        let film = try XCTUnwrap(jellyfin { call, user, token in
            ((call("/Items?Recursive=true&IncludeItemTypes=Movie&userId=\(user)", "GET", token, nil)?["Items"] as? [[String: Any]])?.first)?["Id"] as? String
        }, "the test Jellyfin has no film")
        // The fixture film resumes at 2:30 in other tests: put back after playing.
        addTeardownBlock {
            _ = self.jellyfin { call, user, token in
                call("/UserItems/\(film)/UserData?userId=\(user)", "POST", token, #"{"PlaybackPositionTicks":1500000000,"Played":false}"#)
            }
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "",
            "JF_SERVER": "http://127.0.0.1:8097",
            "JF_USER": "fixture",
            "JF_PASS": "fixture-pass",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
        ]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        // play_item fails until Jellyfin has signed in.
        XCTAssertTrue(wait(30) { !self.mcp("play_item", #"{"item_id":"jellyfin:\#(film)","from_start":true}"#).contains(#""isError":true"#) },
                      "the film cannot be played")
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.exists && state.value as? String == "playing" }, "the film does not play")
        let subtitle = app.staticTexts["player.subtitle"]

        pickTrack({ $0.matching(NSPredicate(format: "label CONTAINS 'English'")).allElementsBoundByIndex.last }, app)
        XCTAssertTrue(subtitle.waitForExistence(timeout: 10), "the chosen subtitle is not shown:\n\(app.debugDescription)")
        XCTAssertTrue(subtitle.label.hasPrefix("Fixture subtitle"), "unexpected subtitle text: \(subtitle.label)")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(subtitle.frame), "the subtitle is off screen: \(subtitle.frame)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "subtitle-shown"
        shot.lifetime = .keepAlways
        add(shot)

        pickTrack({ $0["Off"] }, app)
        XCTAssertTrue(wait(5) { !subtitle.exists }, "the subtitle stays after Off")
        app.buttons["player.close"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
    }

    /// Opens the track menu (controls shown first) and taps the entry `entry` finds among its buttons.
    private func pickTrack(_ entry: (XCUIElementQuery) -> XCUIElement?, _ app: XCUIApplication) {
        if UIDevice.current.userInterfaceIdiom == .phone, XCUIDevice.shared.orientation != .landscapeLeft {
            // Device landscape left is interface landscape right, where the player turns.
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 1)
        }
        let close = app.buttons["player.close"]
        if !close.waitForExistence(timeout: 2) { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 5), "no controls after a tap:\n\(app.debugDescription)")
        let menu = app.descendants(matching: .any)["player.tracks"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "no track menu:\n\(app.debugDescription)")
        menu.tap()
        // Longer than the controls stay without input: the open menu keeps them (and itself).
        Thread.sleep(forTimeInterval: 6)
        let button = entry(app.buttons)
        XCTAssertTrue(button?.waitForExistence(timeout: 5) == true, "no such track in the menu:\n\(app.debugDescription)")
        button?.tap()
    }

    /// Signs in to the test Jellyfin, runs `body` with its API and signs out; nil when it does not answer.
    private func jellyfin<T>(_ body: (_ call: (String, String, String?, String?) -> [String: Any]?, _ user: String, _ token: String) -> T?) -> T? {
        func call(_ path: String, method: String = "GET", token: String? = nil, body: String? = nil) -> [String: Any]? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8097" + path)!)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let client = #"MediaBrowser Client="uitest", Device="uitest", DeviceId="fernsy-uitest-sub-ios", Version="1""#
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
