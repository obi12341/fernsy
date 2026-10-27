import XCTest

/// Shared setup of the Apple TV UI tests: the app with the demo account and its debug MCP
/// server, waiting helpers, screenshots, and on failure the app's log as an attachment.
class FernsyUITestCase: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func launchDemo(_ extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
        ].merging(extra) { $1 }
        app.launch()
        return app
    }

    /// Whether the local test Jellyfin (scripts/jellyfin-test-server.sh) answers on 127.0.0.1:8097.
    /// Tests that need it skip without it (CI has none).
    func jellyfinRunning() -> Bool {
        let done = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:8097/System/Info/Public")!) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 3)
        return ok
    }

    func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    func shot(_ name: String, _ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    override func record(_ issue: XCTIssue) {
        attachLog()
        super.record(issue)
    }

    /// Calls a tool of the app's debug MCP server (port 52325) and returns the raw answer.
    func mcpCall(_ tool: String, _ arguments: String = "{}") -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:52325/mcp")!)
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

    /// The app's log lines (detail level and up) that contain `query`.
    func appLog(_ query: String) -> [String] {
        let text = mcpCall("get_log", #"{"level":"detail","limit":2000,"query":"\#(query)"}"#)
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let result = json["result"] as? [String: Any], let content = result["structuredContent"] as? [String: Any],
              let entries = content["entries"] as? [String] else { return [] }
        return entries
    }

    /// The app's log from its debug MCP server, as an attachment.
    private func attachLog() {
        let text = mcpCall("get_log", #"{"level":"detail","limit":300}"#)
        let log = XCTAttachment(string: text)
        log.name = "app-log"
        log.lifetime = .keepAlways
        add(log)
    }
}

extension XCTestCase {
    /// The app opens on Start: moves to the tab named `name` (Live TV by default) and waits for it.
    func showTab(_ name: String = "Live TV", _ app: XCUIApplication, timeout: TimeInterval = 30) {
        let tab = app.tabBars.firstMatch.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "no \(name) tab:\n\(app.debugDescription)")
        let tabs = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map(\.label)
        for _ in 0..<12 where !tab.hasFocus {
            let focused = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.firstIndex { $0.hasFocus } ?? 0
            let target = tabs.firstIndex(of: name) ?? 0
            XCUIRemote.shared.press(target > focused ? .right : .left)
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(tab.hasFocus, "the \(name) tab has no focus")
        Thread.sleep(forTimeInterval: 1)   // the tab's screen follows the focus
    }
}
