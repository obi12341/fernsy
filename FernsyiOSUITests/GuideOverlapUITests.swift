import XCTest

/// One show at a time per channel (guide-overlapping-listings): channel 101 gets listings that
/// overlap the way some providers send them (`IPTV_TESTEPGOVERLAP`: a second version of the
/// schedule ten minutes later and a placeholder across the shows around now). Its row shows
/// separate cells, none on top of another.
final class GuideOverlapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOverlappingListingsShowSeparateCells() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
            "IPTV_TAB": "live",
            "IPTV_LIVEVIEW": "guide",
            "IPTV_TESTEPGOVERLAP": "101",
        ]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.101.' AND NOT (identifier CONTAINS '.gap.')"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 30), "no listings in the guide:\n\(app.debugDescription)")

        // The full table has arrived, and the clean-up had overlapping listings to drop.
        var dropped = 0
        let deadline = Date().addingTimeInterval(30)
        while dropped == 0, Date() < deadline {
            dropped = log("overlapping dropped").filter { $0.contains("channel 101:") }.compactMap(Self.droppedCount).max() ?? 0
            if dropped == 0 { Thread.sleep(forTimeInterval: 0.5) }
        }
        XCTAssertGreaterThan(dropped, 0, "no overlapping listings were dropped for channel 101: \(log("channel 101:"))")
        Thread.sleep(forTimeInterval: 1)

        let frames = cells.allElementsBoundByIndex.map(\.frame).sorted { $0.minX < $1.minX }
        XCTAssertGreaterThanOrEqual(frames.count, 4, "too few shows to compare:\n\(app.debugDescription)")
        for (a, b) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(a.maxX, b.minX + 0.5, "two cells of channel 101 overlap: \(a) and \(b)")
        }
        XCTAssertFalse(cells.allElementsBoundByIndex.contains { $0.label.contains("TBC") }, "the placeholder is shown")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "guide-overlap"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// "… 49 overlapping dropped" → 49.
    private static func droppedCount(_ line: String) -> Int? {
        guard let end = line.range(of: " overlapping dropped") else { return nil }
        return Int(line[..<end.lowerBound].split(separator: " ").last ?? "")
    }

    /// App log lines (detail and up) containing `query`, via the debug MCP server (port 52326).
    private func log(_ query: String) -> [String] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:52326/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_log","arguments":{"level":"detail","query":"\#(query)","limit":5000}}}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        var text = ""
        URLSession.shared.dataTask(with: request) { data, _, _ in
            text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        // The tool's JSON text is embedded in the JSON-RPC answer: lines are separated by escaped quotes.
        return text.components(separatedBy: "\\\"").filter { $0.contains(query) }
    }
}
