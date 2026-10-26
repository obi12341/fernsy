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
        ]
        app.launch()
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch.waitForExistence(timeout: 30))
        let guideTab = app.tabBars.firstMatch.buttons["Guide"]
        remote.press(.right)
        XCTAssertTrue(waitFor { guideTab.hasFocus }, "Guide tab has no focus")

        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide cells:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "guide"
        shot.lifetime = .keepAlways
        add(shot)

        // Down from the tab bar lands on a show of the first row; walk to the one running now.
        remote.press(.down)
        let focused = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
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

        // A later show: Right until the focused show starts in the future, then Record.
        XCTAssertTrue(focused.waitForExistence(timeout: 10), "focus did not return to the guide")
        for _ in 0..<6 {
            let start = Double(focused.identifier.split(separator: ".").last ?? "") ?? 0
            if start > Date().timeIntervalSince1970 { break }
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        let id = focused.identifier
        remote.press(.select)
        let record = app.sheets.buttons["Record"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5), "no record dialog:\n\(app.debugDescription)")
        XCTAssertTrue(waitFor { record.hasFocus } || { remote.press(.up); return waitFor { record.hasFocus } }())
        remote.press(.select)
        XCTAssertTrue(waitFor { app.buttons[id].value as? String == "scheduled" }, "\(id) is not marked as scheduled")
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
