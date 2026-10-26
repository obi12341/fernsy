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

    /// The app's log from its debug MCP server (port 52325).
    private func attachLog() {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:52325/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_log","arguments":{"level":"detail","limit":300}}}"#.utf8)
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
}
