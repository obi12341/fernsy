import XCTest

/// Start follows the clock (start-live-clock): with the clock set 60 s before a show change on
/// channel 101, its On Now card moves on to the next show without leaving Start.
final class StartClockUITests: FernsyUITestCase {
    func testLiveCardMovesOnToTheNextShow() throws {
        let change = try XCTUnwrap(DemoGuide.nextTitleChange(channel: 101), "no show change in the demo guide")
        // IPTV_CLOCKOFFSET: the app's "now" is 60 s before the change (launching takes a while).
        let offset = Int(change.at.timeIntervalSinceNow) - 60
        // IPTV_EPGSTALE: the guide comes fresh from the server, as the test reads it; a table
        // cached on the simulator from an earlier day can differ.
        let app = launchDemo(["IPTV_CLOCKOFFSET": "\(offset)", "IPTV_EPGSTALE": "1"])
        // The button joins its texts into its value; the show title is in it.
        let card = app.buttons["start.live.101"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "no On Now card for 101:\n\(app.debugDescription)")
        XCTAssertTrue(wait(20) { (card.value as? String)?.contains(change.before) == true }, "the card does not show \"\(change.before)\": \(card.value ?? "nil")")
        shot("start-clock-before", app)
        XCTAssertTrue(wait(75) { (card.value as? String)?.contains(change.after) == true }, "the card did not move on to \"\(change.after)\": \(card.value ?? "nil")")
        shot("start-clock-after", app)
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
