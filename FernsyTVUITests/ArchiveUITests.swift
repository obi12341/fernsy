import XCTest

/// Catch-up (7.1, 7.2): archive channels are marked, the guide pages back into the archive, a
/// past show plays from its start and seeks; with one stream held by a recording it asks first.
/// Runs against a local run of the demo worker (127.0.0.1:8787) when there is one, else against
/// the demo server; skipped while neither serves an archive.
final class ArchiveUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    /// The server to use, or nil (skip) without an archive channel.
    private func archiveServer() -> String? {
        for server in ["http://127.0.0.1:8787", "https://fernsy-demo.mobilistics.workers.dev"] {
            let done = DispatchSemaphore(value: 0)
            var archive = false
            let url = URL(string: "\(server)/player_api.php?username=demo&password=demo&action=get_live_streams")!
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let list = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
                archive = list.contains { "\($0["tv_archive"] ?? 0)" == "1" }
                done.signal()
            }.resume()
            _ = done.wait(timeout: .now() + 5)
            if archive { return server }
        }
        return nil
    }

    /// The first number after `key` in an MCP answer (its JSON is escaped inside the text).
    private func number(_ key: String, in text: String) -> Int? {
        guard let range = text.range(of: key) else { return nil }
        let digits = text[range.upperBound...].drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    private func focusedCell(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.101.' AND hasFocus == true")).firstMatch
    }

    func testPastShowPlaysFromTheArchive() throws {
        guard let server = archiveServer() else { throw XCTSkip("no server with an archive (local demo worker or deployed demo server)") }
        let app = launchDemo(["IPTV_SERVER": server])
        showLiveView("live.view.guide", app)
        XCTAssertTrue(app.descendants(matching: .any)["archive.101"].waitForExistence(timeout: 20), "no archive mark on channel 101:\n\(app.debugDescription)")
        XCTAssertFalse(app.descendants(matching: .any)["archive.104"].exists, "channel 104 has no archive but is marked")

        // Into the first row (channel 101), then Left until the guide shows yesterday.
        let cell = focusedCell(app)
        for direction in [XCUIRemote.Button.down, .right, .right] where !cell.exists {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "no show of channel 101 has focus:\n\(app.debugDescription)")
        // Back until a show that surely ended has focus (begun three hours ago or earlier), past
        // the guide's usual start half an hour back: independent of the time of day.
        let day = app.staticTexts["guide.day"]
        for _ in 0..<40 {
            let start = Double(cell.identifier.split(separator: ".").last ?? "") ?? .infinity
            if start < Date().timeIntervalSince1970 - 3 * 3600 { break }
            remote.press(.left); Thread.sleep(forTimeInterval: 0.4)
        }
        let start = Double(cell.identifier.split(separator: ".").last ?? "") ?? .infinity
        XCTAssertLessThan(start, Date().timeIntervalSince1970 - 3 * 3600, "Left did not page back into the archive:\n\(app.debugDescription)")
        XCTAssertTrue(day.exists, "no day title")
        Thread.sleep(forTimeInterval: 2)
        shot("archive-guide-back", app)

        remote.press(.select)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(40) { state.value as? String == "playing" }, "the archived show does not play:\n\(app.debugDescription)")
        let playing = mcpCall("now_playing")
        XCTAssertTrue(playing.contains("Northern Light"), "not the archive of channel 101: \(playing)")
        shot("archive-playing", app)

        // Ten minutes ahead: the archive is requested again from there.
        _ = mcpCall("seek", #"{"by_seconds":600}"#)
        XCTAssertTrue(wait(40) { state.value as? String == "playing" }, "playback did not continue after the seek")
        let after = mcpCall("now_playing")
        XCTAssertGreaterThanOrEqual(number("position_seconds", in: after) ?? 0, 590, "not 10 minutes into the show: \(after)")
    }

    /// 7.2: one stream (IPTV_MAXCONN=1) held by a recording (IPTV_TESTRECORD on channel 104).
    func testArchiveAsksWhenARecordingHoldsTheStream() throws {
        guard let server = archiveServer() else { throw XCTSkip("no server with an archive") }
        let app = launchDemo(["IPTV_SERVER": server, "IPTV_MAXCONN": "1", "IPTV_TESTRECORD": "104:0:600", "IPTV_FRESHRECORDINGS": "1"])
        showLiveView("live.view.guide", app)
        XCTAssertTrue(wait(30) { self.mcpCall("list_recordings").contains("recording") }, "the test recording did not start")
        let cell = focusedCell(app)
        for direction in [XCUIRemote.Button.down, .right, .right] where !cell.exists {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "no show of channel 101 has focus")
        // Left to a show that is surely over: one that began four hours ago or earlier (a running
        // show plays the channel live instead).
        for _ in 0..<20 {
            let start = Double(cell.identifier.split(separator: ".").last ?? "") ?? .infinity
            if start < Date().timeIntervalSince1970 - 4 * 3600 { break }
            remote.press(.left); Thread.sleep(forTimeInterval: 0.5)
        }
        remote.press(.select)
        let question = app.alerts.firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 10), "no question before stopping the recording:\n\(app.debugDescription)")
        XCTAssertTrue(question.buttons["Keep Recording"].exists, "no \"Keep Recording\"")
        shot("archive-asks", app)
    }
}
