import XCTest

/// The app's debug MCP server for this test process: its own port, so tests on parallel
/// simulators (`-parallel-testing-worker-count`) each talk to their own app (faster-ui-tests).
enum URLForTest {
    static let port = 52400 + Int(getpid() % 500)
    static var mcp: URL { URL(string: "http://127.0.0.1:\(port)/mcp")! }
}

extension XCUIApplication {
    /// Launches with this test process's debug MCP port.
    func launchForTest() {
        launchEnvironment["IPTV_MCPPORT"] = String(URLForTest.port)
        // Diagnostics for tests stopped after their time limit on CI (fix/tv-ci-hang-diagnostics):
        // every launch's log is kept, and a blocked main thread is logged.
        launchEnvironment["IPTV_LOGARCHIVE"] = "1"
        launchEnvironment["IPTV_HANGWATCH"] = "1"
        launch()
    }
}

/// Shared setup of the Apple TV UI tests: the app with the demo account and its debug MCP
/// server, waiting helpers, screenshots, and on failure the app's log as an attachment.
class FernsyUITestCase: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func launchDemo(_ extra: [String: String] = [:], arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
        ].merging(extra) { $1 }
        app.launchForTest()
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

    /// Calls a tool of the app's debug MCP server (this test process's port) and returns the raw answer.
    func mcpCall(_ tool: String, _ arguments: String = "{}") -> String {
        var request = URLRequest(url: URLForTest.mcp)
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

    /// Waits until the app's log has a line containing `query` (tvos-uitest-shards: a state, not a
    /// fixed time). False after `timeout`.
    @discardableResult
    func waitForLog(_ query: String, timeout: TimeInterval = 15) -> Bool {
        wait(timeout) { !self.appLog(query).isEmpty }
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
        let tab = tabButton(name, app)
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "no \(name) tab:\n\(app.debugDescription)")
        let tabs = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map(\.label)
        // Focus inside a screen: Back reaches the tab bar.
        for _ in 0..<2 where !app.tabBars.firstMatch.buttons.allElementsBoundByIndex.contains(where: \.hasFocus) {
            XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 0.6)
        }
        // Short pauses, not a wait for each focus move: the loop checks the focus after every
        // press anyway, and a focus-move wait costs about a second (faster-ui-tests, as built).
        for _ in 0..<12 where !tab.hasFocus {
            let focused = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.firstIndex { $0.hasFocus } ?? 0
            let target = tabs.firstIndex(of: tab.label) ?? 0
            XCUIRemote.shared.press(target > focused ? .right : .left)
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(tab.hasFocus, "the \(name) tab has no focus")
        // The tab's screen follows the focus a moment later: wait until the tab is selected.
        let tabView = app.descendants(matching: .any)["tabs"]
        let selected = Self.tabValues[name] ?? name
        XCTAssertTrue(waitUntil(10) { tabView.value as? String == selected },
                      "the \(name) tab was not selected (\(tabView.value as? String ?? "-"))")
    }

    /// A tab bar button by its English title, also when the app runs in German.
    func tabButton(_ name: String, _ app: XCUIApplication) -> XCUIElement {
        let titles = [name, Self.germanTabTitles[name]].compactMap { $0 }
        return app.tabBars.firstMatch.buttons.matching(NSPredicate(format: "label IN %@", titles)).firstMatch
    }

    static var germanTabTitles: [String: String] {
        ["Movies": "Filme", "Series": "Serien", "Recordings": "Aufnahmen", "Search": "Suche",
         "Settings": "Einstellungen"]
    }

    /// Presses `moves` in turn (each waiting for the focus to move) until `element` has focus, at
    /// most `limit` presses; fails naming what has focus instead (faster-ui-tests).
    func focus(_ element: XCUIElement, in app: XCUIApplication, moves: [XCUIRemote.Button], limit: Int = 12,
               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "no \(element):\n\(app.debugDescription)", file: file, line: line)
        var presses = 0
        while !element.hasFocus && presses < limit {
            pressAndWaitForFocusMove(moves[presses % moves.count], app)
            presses += 1
        }
        XCTAssertTrue(element.hasFocus, "\(element.identifier) has no focus; focus is on \(focusKey(app))", file: file, line: line)
    }

    /// Waits until `element` exists and has `value` (e.g. `player.state` "playing"); false after `timeout`.
    @discardableResult
    func waitFor(_ element: XCUIElement, value: String, timeout: TimeInterval = 20) -> Bool {
        waitUntil(timeout) { element.exists && element.value as? String == value }
    }

    /// The `tabs` element's value (the selected tab, RootScreen) for each tab title.
    static var tabValues: [String: String] {
        ["Start": "start", "Live TV": "live", "Movies": "films", "Series": "series", "Jellyfin": "jellyfin",
         "Recordings": "recordings", "Search": "search", "Settings": "settings"]
    }

    /// Live TV in the view of the switch pill `id` ("live.view.list" or "live.view.guide"),
    /// with focus left on that pill (tvos-live-and-guide).
    func showLiveView(_ id: String, _ app: XCUIApplication) {
        let pill = app.buttons[id]
        let pills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'live.view.'"))
        let inLiveTV = pill.exists && !app.tabBars.firstMatch.buttons.allElementsBoundByIndex.contains(where: \.hasFocus)
        if !inLiveTV { showTab("Live TV", app) }
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "no \(id):\n\(app.debugDescription)")
        // From the tab bar Down, from inside Live TV Up reaches the switch.
        for _ in 0..<6 where !pills.allElementsBoundByIndex.contains(where: \.hasFocus) {
            XCUIRemote.shared.press(inLiveTV ? .up : .down); Thread.sleep(forTimeInterval: 0.5)
        }
        for direction in [XCUIRemote.Button.right, .left, .right] where !pill.hasFocus {
            XCUIRemote.shared.press(direction); Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(pill.hasFocus, "\(id) has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntil(5) { pill.value as? String == "selected" }, "\(id) was not selected")
        // Kept: the view swaps with an animation, and no state marks its end.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Live TV's first channel row with focus: Down past the view switch into the column, Right
    /// into the rows, Up to the first one.
    @discardableResult
    func focusFirstLiveChannel(_ app: XCUIApplication) -> XCUIElement {
        showTab("Live TV", app)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30), "the channel list did not appear")
        for direction in [XCUIRemote.Button.down, .down, .right, .up, .up, .up] where !first.hasFocus {
            XCUIRemote.shared.press(direction)
            Thread.sleep(forTimeInterval: 0.8)
        }
        XCTAssertTrue(first.hasFocus, "the first channel has no focus:\n\(app.debugDescription)")
        return first
    }

    // Waiting for a state instead of a fixed time (tvos-uitest-shards): a fixed sleep is too short
    // on a slow runner and too long on a fast one. Sleeps that stay are commented with why.

    /// Waits until `element` has focus; false after `timeout`.
    @discardableResult
    func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        waitUntil(timeout) { element.exists && element.hasFocus }
    }

    /// Back until the film, episode or recording player is closed: with the timeline showing,
    /// the first press only hides it (tvos-back-closes-overlay). False if it stays open.
    @discardableResult
    func closePlayer(_ app: XCUIApplication) -> Bool {
        let state = app.descendants(matching: .any)["player.state"]
        for _ in 0..<3 where state.exists {
            XCUIRemote.shared.press(.menu)
            _ = waitUntil(2) { !state.exists }
        }
        return !state.exists
    }

    /// Waits until the player (live, film or recording) has taken focus: it does so a moment after
    /// it appears, and a press before that goes nowhere. The player reports it as its surface's value.
    @discardableResult
    func waitForPlayerFocus(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let surface = app.descendants(matching: .any)["player.surface"]
        return waitUntil(timeout) { surface.exists && surface.value as? String == "focused" }
    }

    /// Which element has focus, as identifier, label and frame ("" when none).
    func focusKey(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? "\(focused.identifier)|\(focused.label)|\(focused.frame)" : ""
    }

    /// Presses `button` and waits until focus has moved (or `timeout`), so the next press does not
    /// get lost while the focus engine is still moving. False when focus did not move.
    @discardableResult
    func pressAndWaitForFocusMove(_ button: XCUIRemote.Button, _ app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let before = focusKey(app)
        XCUIRemote.shared.press(button)
        return waitUntil(timeout) { self.focusKey(app) != before }
    }

    /// Opens the keyboard of the focused text field, types `text` and closes it with Back, then
    /// waits until the field has focus again (the keyboard is gone).
    func typeOnKeyboard(_ text: String, _ app: XCUIApplication) {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let id = focused.exists ? focused.identifier : ""
        XCUIRemote.shared.press(.select)
        app.typeText(text)
        XCUIRemote.shared.press(.menu)
        if !id.isEmpty {
            let field = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND hasFocus == true", id))
            XCTAssertTrue(waitUntil(10) { field.firstMatch.exists }, "\(id) has no focus after the keyboard:\n\(app.debugDescription)")
        }
    }

    func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }
}
