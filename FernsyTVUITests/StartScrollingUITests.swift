import XCTest

/// Scrolling Start with a provider-sized catalog (tvos-start-scrolling 1.2, 3.1): 30,000 films
/// and series from the demo server, Start scrolled to the last row and back while the app counts
/// late frames (IPTV_FRAMESTATS).
final class StartScrollingUITests: FernsyUITestCase {
    /// Late frames logged since `skip` log lines ("frames: 7 late of 60").
    private func lateFrames(after skip: Int, _ app: XCUIApplication) -> (late: Int, lines: [String]) {
        let lines = Array(appLog("frames:").dropFirst(skip))
        let late = lines.compactMap { line in
            line.range(of: #"frames: (\d+) late"#, options: .regularExpression).flatMap { Int(line[$0].split(separator: " ")[1]) }
        }.reduce(0, +)
        return (late, lines)
    }

    func testScrollingALargeCatalog() {
        let app = launchDemo(["IPTV_TESTBIGCATALOG": "30000", "IPTV_FRAMESTATS": "1"])
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 60), "Start did not load")
        // The catalog, images and guide settle first.
        XCTAssertTrue(wait(30) { !self.appLog("films, ").isEmpty }, "the films did not load")
        Thread.sleep(forTimeInterval: 5)
        let before = appLog("frames:").count
        let started = Date()
        for _ in 0..<14 { remote.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        for _ in 0..<14 { remote.press(.up); Thread.sleep(forTimeInterval: 0.5) }
        Thread.sleep(forTimeInterval: 1.5)
        let result = lateFrames(after: before, app)
        let seconds = Int(Date().timeIntervalSince(started))
        let report = XCTAttachment(string: "late frames while scrolling: \(result.late) in \(seconds) s\n" + result.lines.joined(separator: "\n"))
        report.name = "start-scrolling-frames"
        report.lifetime = .keepAlways
        add(report)
        print("START_SCROLL_LATE_FRAMES \(result.late) in \(seconds) s")
        // CI's simulator renders without a GPU (35–47 frames a second there even at rest): the
        // count is reported but only judged on a Mac (TEST_RUNNER_FERNSY_CI from tests.yml).
        if ProcessInfo.processInfo.environment["FERNSY_CI"] == "1" { return }
        // 136–139 before tvos-start-scrolling, 14 after it.
        XCTAssertLessThanOrEqual(result.late, 40, "Start stutters while scrolling:\n" + result.lines.joined(separator: "\n"))
    }
}
