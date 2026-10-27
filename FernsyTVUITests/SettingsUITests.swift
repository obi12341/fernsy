import XCTest

/// Settings (tvos-live 5.3): the rows of the design, and new padding applies to a recording
/// planned afterwards (checked through the debug MCP's record and list_recordings).
final class SettingsUITests: FernsyUITestCase {
    func testPaddingApplies() throws {
        let app = launchDemo(["IPTV_FRESHRECORDINGS": "1"])
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch.waitForExistence(timeout: 30))
        let gear = app.tabBars.firstMatch.buttons["Settings"]
        for _ in 0..<3 { remote.press(.right); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(wait(5) { gear.hasFocus }, "the gear has no focus")
        let row = app.buttons["settings.recordings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no settings:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["settings.version"].exists)
        XCTAssertFalse(app.staticTexts["Jugendschutz"].exists || app.staticTexts["Youth Protection"].exists)
        shot("settings", app)

        remote.press(.down)
        for _ in 0..<6 where !row.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(row.hasFocus, "the Recordings row has no focus")
        remote.press(.select)
        pick("padBefore.2", app)
        remote.press(.down)
        pick("padAfter.5", app)
        remote.press(.menu)
        XCTAssertTrue(wait(5) { row.label.contains("2") && row.label.contains("5") }, "the row does not show the padding: \(row.label)")

        // Record the show on now: it starts two minutes early.
        let answer = try mcp("record", #"{"channel_id": 101}"#)
        let recordings = try XCTUnwrap(answer["recordings"] as? [[String: Any]])
        let recording = try XCTUnwrap(recordings.first { ($0["channel_id"] as? Int) == 101 })
        let formatter = ISO8601DateFormatter()
        let recordStart = try XCTUnwrap(formatter.date(from: recording["record_start"] as? String ?? ""))
        let showStart = try XCTUnwrap(formatter.date(from: recording["show_start"] as? String ?? ""))
        XCTAssertEqual(showStart.timeIntervalSince(recordStart), 120, accuracy: 1, "the recording does not start two minutes early")
        _ = try mcp("cancel_recording", #"{"recording_id": "\#(recording["recording_id"] as? String ?? "")", "delete": true}"#)

        // Back to the defaults (10 and 10), so other runs are not affected.
        XCTAssertTrue(wait(5) { row.hasFocus }, "the Recordings row has no focus again")
        remote.press(.select)
        pick("padBefore.10", app)
        remote.press(.down)
        pick("padAfter.10", app)
        remote.press(.menu)
    }

    /// Moves Left or Right in a row of choices until `id` has focus, then clicks it.
    private func pick(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no \(id):\n\(app.debugDescription)")
        for direction in [XCUIRemote.Button.left, .left, .left, .left, .left, .right, .right, .right, .right, .right] where !button.hasFocus {
            XCUIRemote.shared.press(direction)
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(button.hasFocus, "\(id) has no focus")
        XCUIRemote.shared.press(.select)
    }

    /// Calls a tool of the app's debug MCP server and returns its structured result.
    private func mcp(_ tool: String, _ arguments: String) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:52325/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        var body: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in body = data; done.signal() }.resume()
        _ = done.wait(timeout: .now() + 10)
        let json = try JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: Any]
        let result = try XCTUnwrap(json?["result"] as? [String: Any])
        return try XCTUnwrap(result["structuredContent"] as? [String: Any])
    }
}
