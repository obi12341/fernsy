import XCTest

/// Long channel names in the guide (tvos-guide-name-ticker 2.2, 2.3) on the demo server: the
/// name of channel 101, "Northern Light 1" (shown without its "HD"), does not fit the channel
/// column and slides while its row has focus; "Current TV" (104) fits and stays still.
final class GuideNameTickerUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func name(_ channel: Int, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["guide.name.\(channel)"]
    }

    private func moving(_ channel: Int, _ app: XCUIApplication) -> Bool {
        name(channel, app).value as? String == "moving"
    }

    /// The channel id of the guide cell with focus ("guide.<channel>.<start>" or ".gap.").
    private func focusedChannel(_ app: XCUIApplication) -> Int? {
        let cell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.' AND hasFocus == true")).firstMatch
        guard cell.exists else { return nil }
        return Int(cell.identifier.split(separator: ".").dropFirst().first ?? "")
    }

    /// Opens the guide and moves focus into its first row (channel 101).
    private func focusTheFirstRow(_ app: XCUIApplication) {
        showLiveView("live.view.guide", app)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "no guide cells")
        for direction in [XCUIRemote.Button.down, .right, .right] where focusedChannel(app) == nil {
            remote.press(direction); Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertEqual(focusedChannel(app), 101, "focus is not in the first row:\n\(app.debugDescription)")
    }

    /// Moves focus down until it is in `channel`'s row.
    private func moveDown(to channel: Int, _ app: XCUIApplication) {
        for _ in 0..<6 where focusedChannel(app) != channel { remote.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertEqual(focusedChannel(app), channel, "focus did not reach row \(channel):\n\(app.debugDescription)")
    }

    /// What the motion costs (as for the living hero): the late frames logged so far, attached and
    /// printed. Both tests take the same eight screenshots first, one with the name moving and
    /// one with it at rest, so the two numbers can be compared.
    private func attachLateFrames(_ state: String, _ app: XCUIApplication) {
        let lines = appLog("frames:")
        let late = lines.compactMap { line in
            line.range(of: #"frames: (\d+) late"#, options: .regularExpression).flatMap { Int(line[$0].split(separator: " ")[1]) }
        }
        let report = XCTAttachment(string: "late frames with the name \(state): \(late)\n" + lines.joined(separator: "\n"))
        report.name = "guide-name-frames-\(state)"
        report.lifetime = .keepAlways
        add(report)
        print("GUIDE_NAME_LATE_FRAMES \(state) \(late.reduce(0, +)) in \(lines.count) lines: \(late)")
    }

    /// The name's place on screen, as raw pixels.
    private func pixels(of element: XCUIElement) -> Data {
        let image = XCUIScreen.main.screenshot().image
        let scale = image.scale, frame = element.frame
        let crop = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
        guard let part = image.cgImage?.cropping(to: crop), let data = part.dataProvider?.data else { return Data() }
        return data as Data
    }

    func testALongNameSlidesWhileItsRowHasFocus() {
        let app = launchDemo(["IPTV_FRAMESTATS": "1"])
        focusTheFirstRow(app)
        let long = name(101, app)
        XCTAssertTrue(long.exists, "no name element for channel 101:\n\(app.debugDescription)")
        XCTAssertEqual(long.label, "Northern Light 1", "the name's label is not the full name")
        XCTAssertTrue(wait(5) { self.moving(101, app) }, "the name of the focused row does not move")

        // It slides: its place on screen looks different over the next seconds.
        var looks = Set<Data>()
        for step in 0..<8 {
            looks.insert(pixels(of: long))
            shot("guide-name-\(step)", app)
        }
        XCTAssertGreaterThan(looks.count, 2, "the name's place on screen did not change while it was moving")
        attachLateFrames("moving", app)

        // Right to the next show of the same channel: it keeps sliding, it does not start over.
        remote.press(.right)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(focusedChannel(app), 101, "Right left the row")
        XCTAssertTrue(moving(101, app), "the name stopped when focus moved within the row")
        let starts = appLog("guide row 101: name ticker started")
        XCTAssertEqual(starts.count, 1, "the name started over within its row: \(starts)")

        // Down: the row left behind shows the shortened name again.
        remote.press(.down)
        XCTAssertTrue(wait(3) { !self.moving(101, app) }, "the name still moves after focus left its row")
        XCTAssertNotEqual(focusedChannel(app), 101, "Down did not leave the row")
        shot("guide-name-left", app)

        // A name that fits does not move.
        moveDown(to: 104, app)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(moving(104, app), "the name of channel 104 fits and moves all the same")
        XCTAssertTrue(appLog("guide row 104: name ticker started").isEmpty, "the ticker started for a name that fits")
    }

    func testReduceMotionKeepsTheNameShortened() {
        let app = launchDemo(["IPTV_TESTREDUCEMOTION": "1", "IPTV_FRAMESTATS": "1"])
        focusTheFirstRow(app)
        let long = name(101, app)
        XCTAssertTrue(long.exists, "no name element for channel 101:\n\(app.debugDescription)")
        var looks = Set<Data>()
        for step in 0..<8 {
            XCTAssertFalse(moving(101, app), "the name moves although motion is reduced")
            looks.insert(pixels(of: long))
            shot("guide-name-reduced-\(step)", app)
        }
        XCTAssertEqual(looks.count, 1, "the name's place on screen changed although motion is reduced")
        XCTAssertTrue(appLog("name ticker started").isEmpty, "the ticker started although motion is reduced")
        attachLateFrames("at rest", app)
    }
}
