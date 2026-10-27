import XCTest

/// The player (tvos-live 4.2, 4.3): time behind live in the overlay, back to live with a click,
/// the channel strip with Down, and the audio tab.
final class PlayerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOverlayStripAndTracks() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
        ]
        app.launch()
        let remote = XCUIRemote.shared
        showTab("Live TV", app)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        for _ in 0..<6 where !first.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.2) }
        let firstId = first.identifier
        remote.press(.select)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "not playing")

        // 20 s of buffer, then 20 s back: the overlay shows the time behind live.
        Thread.sleep(forTimeInterval: 20)
        remote.press(.left)
        remote.press(.left)
        shot("after-left", app)
        let behind = app.descendants(matching: .any)["player.behind"]
        XCTAssertTrue(behind.waitForExistence(timeout: 10), "no time behind live:\n\(app.debugDescription)")
        XCTAssertTrue((behind.label).hasPrefix("−0:"), "unexpected \(behind.label)")
        shot("player", app)
        remote.press(.select)
        XCTAssertTrue(wait(10) { !behind.exists }, "a click did not go back to live")

        // Down: the strip, starting at the playing channel; focus on the next one; click tunes it.
        remote.press(.down)
        let strip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strip.'"))
        XCTAssertTrue(strip.firstMatch.waitForExistence(timeout: 5), "no channel strip")
        let playingCard = app.buttons["strip." + firstId.dropFirst("channel.".count)]
        XCTAssertTrue(playingCard.exists && playingCard.label.contains("On now"), "the strip does not show the playing channel as on now")
        XCTAssertFalse(playingCard.hasFocus, "focus should start on the next channel")
        shot("zap", app)
        remote.press(.select)
        XCTAssertTrue(wait(5) { !strip.firstMatch.exists }, "the strip stayed open")
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the zapped channel does not play")

        // Up twice, Right twice: the Audio tab, click shows its panel.
        remote.press(.up)
        remote.press(.up)
        remote.press(.right)
        remote.press(.right)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Audio"].waitForExistence(timeout: 5), "no audio panel:\n\(app.debugDescription)")
        remote.press(.menu)
    }

    /// On failure: the app's log from its debug MCP server (port 52325), as an attachment.
    override func record(_ issue: XCTIssue) {
        attachLog()
        super.record(issue)
    }

    private func attachLog() {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:52325/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_log","arguments":{"level":"detail","limit":200}}}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        var text = "no answer"
        URLSession.shared.dataTask(with: request) { data, _, _ in
            text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no data"
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        let log = XCTAttachment(string: text)
        log.name = "app-log"
        log.lifetime = .keepAlways
        add(log)
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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
