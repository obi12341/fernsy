import XCTest

/// Start follows the clock on iPhone and iPad (start-live-clock): with the clock set 60 s before
/// a show change on channel 101, its On Now card moves on to the next show without leaving Start.
final class StartClockUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testLiveCardMovesOnToTheNextShow() throws {
        let change = try XCTUnwrap(DemoGuide.nextTitleChange(channel: 101), "no show change in the demo guide")
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            // The app's "now" is 60 s before the change (launching takes a while).
            "IPTV_CLOCKOFFSET": "\(Int(change.at.timeIntervalSinceNow) - 60)",
            // The guide fresh from the server, as the test reads it (a cached table can differ).
            "IPTV_EPGSTALE": "1",
        ]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        // The button joins its texts into its value; the show title is in it.
        let card = app.buttons["start.live.101"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "no On Now card for 101:\n\(app.debugDescription)")
        XCTAssertTrue(wait(20) { (card.value as? String)?.contains(change.before) == true }, "the card does not show \"\(change.before)\": \(card.value ?? "nil")")
        XCTAssertTrue(wait(75) { (card.value as? String)?.contains(change.after) == true }, "the card did not move on to \"\(change.after)\": \(card.value ?? "nil")")
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

/// The demo server's guide, read directly (the app's clock is shifted, the server's is not).
enum DemoGuide {
    /// The first upcoming time on `channel` where the show title changes.
    static func nextTitleChange(channel: Int) -> (at: Date, before: String, after: String)? {
        let url = URL(string: "https://fernsy-demo.mobilistics.workers.dev/player_api.php?username=demo&password=demo&action=get_short_epg&stream_id=\(channel)&limit=12")!
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let listings = json["epg_listings"] as? [[String: Any]] else { return nil }
        let shows = listings.compactMap { item -> (title: String, start: Date, end: Date)? in
            guard let title = (item["title"] as? String).flatMap({ Data(base64Encoded: $0) }).flatMap({ String(data: $0, encoding: .utf8) }),
                  let start = (item["start_timestamp"] as? String).flatMap(Double.init),
                  let end = (item["stop_timestamp"] as? String).flatMap(Double.init) else { return nil }
            return (title, Date(timeIntervalSince1970: start), Date(timeIntervalSince1970: end))
        }
        for (a, b) in zip(shows, shows.dropFirst()) where a.end > Date().addingTimeInterval(60) && a.title != b.title && a.end == b.start {
            return (a.end, a.title, b.title)
        }
        return nil
    }
}
