import XCTest

/// The guide (tvos-live 4.1): a running show plays its channel, a later one can be scheduled.
final class GuideUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testPlayAndScheduleFromTheGuide() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_FRESHRECORDINGS": "1",
        ]
        app.launchForTest()
        let remote = XCUIRemote.shared
        showLiveView("live.view.guide", app)

        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide cells:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "guide"
        shot.lifetime = .keepAlways
        add(shot)

        // Down from the switch lands on the rail or a show of the first row; walk to the one running now.
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
        for direction in [XCUIRemote.Button.down, .right, .right] where !focused.exists {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "no show has focus:\n\(app.debugDescription)")
        var running = false
        for _ in 0..<6 {
            let start = Double(focused.identifier.split(separator: ".").last ?? "") ?? 0
            if start <= Date().timeIntervalSince1970 && !isPastNext(focused, in: app) { running = true; break }
            remote.press(start > Date().timeIntervalSince1970 ? .left : .right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(running, "no running show found")
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["player.state"].waitForExistence(timeout: 15), "the player did not open")
        remote.press(.menu)

        // A later show: Right until the focused show starts at least 30 minutes from now, then
        // Record. A show starting sooner may already be recording because of the padding before
        // it, and its dialog then offers Stop Recording instead of Don't Record (CI, 2026-11-26).
        XCTAssertTrue(focused.waitForExistence(timeout: 10), "focus did not return to the guide")
        var later = false
        for _ in 0..<10 {
            let start = Double(focused.identifier.split(separator: ".").last ?? "") ?? 0
            if start > Date().timeIntervalSince1970 + 30 * 60 { later = true; break }
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(later, "no show starting in 30 minutes or later:\n\(app.debugDescription)")
        let id = focused.identifier
        // Scheduled by an earlier run (recordings stay in the simulator's Caches): unschedule first.
        if app.buttons[id].value as? String == "scheduled" { choose("Don’t Record", app) }
        choose("Record", app)
        XCTAssertTrue(waitFor { app.buttons[id].value as? String == "scheduled" }, "\(id) is not marked as scheduled")
        choose("Don’t Record", app)
        XCTAssertTrue(waitFor { app.buttons[id].value as? String != "scheduled" }, "\(id) is still scheduled")
    }

    /// The long-press menu (guide-long-press-record 2.2): the running show is recorded from it,
    /// listed as recording, and stopped from the same menu, which then lists it as done.
    func testRecordTheRunningShowFromTheGuide() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_FRESHRECORDINGS": "1",
            "IPTV_MCP": "1",
            "IPTV_MCPTOKEN": "test",
        ]
        app.launchForTest()
        let remote = XCUIRemote.shared
        showLiveView("live.view.guide", app)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide cells:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 2)
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
        for direction in [XCUIRemote.Button.down, .right, .right] where !focused.exists {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "no show has focus:\n\(app.debugDescription)")
        var running = false
        for _ in 0..<6 {
            let start = Double(focused.identifier.split(separator: ".").last ?? "") ?? 0
            if start <= Date().timeIntervalSince1970 && !isPastNext(focused, in: app) { running = true; break }
            remote.press(start > Date().timeIntervalSince1970 ? .left : .right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(running, "no running show found")
        let id = focused.identifier
        let cell = app.buttons[id]

        pick("record.circle", app)
        XCTAssertTrue(waitFor(10) { cell.value as? String == "scheduled" }, "\(id) is not marked as recorded")
        XCTAssertTrue(waitFor(20) { self.recordings().range(of: #""status"\s*:\s*"recording""#, options: .regularExpression) != nil }, "Recordings does not list it as recording: \(recordings())")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "guide-recording"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(waitFor { focused.identifier == id }, "focus left \(id) for \(focused.identifier) after the menu")
        pick("stop.circle", app)
        XCTAssertTrue(waitFor(10) { cell.value as? String != "scheduled" }, "\(id) is still marked")
        XCTAssertTrue(waitFor(10) { self.recordings().range(of: #""status"\s*:\s*"done""#, options: .regularExpression) != nil }, "Recordings does not list it as done: \(recordings())")
    }

    /// The menu in German on a running show, for the user (guide-long-press-record 3.2).
    func testMenuInGerman() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
            "IPTV_FRESHRECORDINGS": "1",
        ]
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchForTest()
        let remote = XCUIRemote.shared
        showLiveView("live.view.guide", app)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide cells:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 2)
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
        for direction in [XCUIRemote.Button.down, .right, .right] where !focused.exists {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "no show has focus:\n\(app.debugDescription)")
        for _ in 0..<6 {
            let start = Double(focused.identifier.split(separator: ".").last ?? "") ?? 0
            if start <= Date().timeIntervalSince1970 && !isPastNext(focused, in: app) { break }
            remote.press(start > Date().timeIntervalSince1970 ? .left : .right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        remote.press(.select, forDuration: 1.5)
        let watch = app.cells.containing(NSPredicate(format: "label == %@", "Sender ansehen")).firstMatch
        XCTAssertTrue(watch.waitForExistence(timeout: 5), "no German menu:\n\(app.debugDescription)")
        XCTAssertTrue(app.cells.containing(NSPredicate(format: "label == %@", "Aufnehmen")).firstMatch.exists, "no Aufnehmen")
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "menu-de"
        shot.lifetime = .keepAlways
        add(shot)
        remote.press(.menu)
    }

    /// Long-presses the focused show and picks the menu entry with `symbol` (tvOS shows the
    /// entries as cells holding their symbol, as in LiveTVUITests).
    private func pick(_ symbol: String, _ app: XCUIApplication) {
        XCUIRemote.shared.press(.select, forDuration: 1.5)
        let entry = app.cells.containing(.any, identifier: symbol).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "no “\(symbol)” in the menu:\n\(app.debugDescription)")
        for _ in 0..<6 where !entry.hasFocus { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(entry.hasFocus, "“\(symbol)” has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitFor { !entry.exists }, "the menu stayed open")
    }

    /// The `list_recordings` answer of the app's debug MCP server.
    private func recordings() -> String {
        var request = URLRequest(url: URLForTest.mcp)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_recordings","arguments":{}}}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        var text = ""
        URLSession.shared.dataTask(with: request) { data, _, _ in
            text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        // The tool's JSON is embedded as a string: unescape its quotes.
        return text.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n")
    }

    /// Clicks the focused show and picks `title` in its dialog.
    private func choose(_ title: String, _ app: XCUIApplication) {
        XCUIRemote.shared.press(.select)
        let button = app.sheets.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no “\(title)” in the dialog:\n\(app.debugDescription)")
        // The dialog lays its buttons out in a column or, with two, side by side.
        for direction in [XCUIRemote.Button.up, .right, .up, .right] where !waitFor(1.5, { button.hasFocus }) {
            XCUIRemote.shared.press(direction)
        }
        XCTAssertTrue(waitFor { button.hasFocus }, "“\(title)” has no focus:\n\(app.debugDescription)")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitFor { !button.exists }, "the dialog stayed open")
    }

    /// The focused show is running when the next cell in its row starts after now.
    private func isPastNext(_ cell: XCUIElement, in app: XCUIApplication) -> Bool {
        let parts = cell.identifier.split(separator: ".")
        guard parts.count == 3, let start = Double(parts[2]) else { return true }
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "guide.\(parts[1]).")).allElementsBoundByIndex
        let starts = row.compactMap { Double($0.identifier.split(separator: ".").last ?? "") }.sorted()
        guard let next = starts.first(where: { $0 > start }) else { return false }
        return next <= Date().timeIntervalSince1970
    }

    private func waitFor(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
}
