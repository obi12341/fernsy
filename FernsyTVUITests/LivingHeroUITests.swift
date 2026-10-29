import XCTest

/// The large entry's living backdrop (tvos-living-hero 3.1): with focus on the entry the backdrop
/// moves, so two screenshots seconds apart differ beside the text; with focus in the rows it
/// rests and they are equal.
final class LivingHeroUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    /// The backdrop right of the entry's text, below the tab bar, as raw pixels.
    private func backdropPixels(_ app: XCUIApplication) -> Data {
        let image = XCUIScreen.main.screenshot().image
        let scale = image.scale
        let crop = CGRect(x: 1300 * scale, y: 160 * scale, width: 520 * scale, height: 340 * scale)
        guard let part = image.cgImage?.cropping(to: crop), let data = part.dataProvider?.data else { return Data() }
        return data as Data
    }

    func testBackdropMovesOnlyWithFocus() {
        let app = launchDemo(["IPTV_FRAMESTATS": "1"])
        let play = app.buttons["start.hero.resume"]
        XCTAssertTrue(play.waitForExistence(timeout: 30), "no large entry")
        let backdrop = app.otherElements["start.backdrop"]
        XCTAssertTrue(backdrop.waitForExistence(timeout: 10), "no backdrop:\n\(app.debugDescription)")
        // Focus on "Play" or "Info" of the large entry.
        let hero = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'start.hero.' AND hasFocus == true")).firstMatch
        // Focus starts in the tab bar: the backdrop rests there.
        if !hero.exists {
            XCTAssertEqual(backdrop.value as? String, "resting")
            remote.press(.down)
        }
        XCTAssertTrue(wait(10) { hero.exists }, "the large entry has no focus:\n\(app.debugDescription)")
        XCTAssertTrue(wait(5) { backdrop.value as? String == "moving" }, "the backdrop does not move")
        // The film's details (with its backdrop) load after Start shows. Kept: no state marks that
        // the backdrop image has arrived.
        Thread.sleep(forTimeInterval: 4)
        let framesBefore = appLog("frames:").count
        shot("hero-moving-0s", app)
        let first = backdropPixels(app)
        Thread.sleep(forTimeInterval: 6)
        shot("hero-moving-6s", app)
        XCTAssertNotEqual(first, backdropPixels(app), "the backdrop did not move while the large entry had focus")
        // The motion must not cost frames (tvos-living-hero 3.2): late frames while it runs.
        let lines = Array(appLog("frames:").dropFirst(framesBefore))
        let late = lines.compactMap { line in
            line.range(of: #"frames: (\d+) late"#, options: .regularExpression).flatMap { Int(line[$0].split(separator: " ")[1]) }
        }.reduce(0, +)
        let report = XCTAttachment(string: "late frames while the backdrop moves: \(late)\n" + lines.joined(separator: "\n"))
        report.name = "hero-moving-frames"
        report.lifetime = .keepAlways
        add(report)
        print("HERO_MOVING_LATE_FRAMES \(late) in \(lines.count) lines")
        XCTAssertLessThanOrEqual(late, 10, "the moving backdrop drops frames:\n" + lines.joined(separator: "\n"))

        remote.press(.down)
        XCTAssertTrue(wait(10) { !hero.exists }, "focus stayed on the large entry")
        XCTAssertTrue(wait(5) { backdrop.value as? String == "resting" }, "the backdrop did not rest")
        // Let the scroll and the backdrop's fade settle.
        Thread.sleep(forTimeInterval: 2)
        let resting = backdropPixels(app)
        shot("hero-resting-0s", app)
        Thread.sleep(forTimeInterval: 4)
        shot("hero-resting-4s", app)
        XCTAssertEqual(resting, backdropPixels(app), "the backdrop moved while the rows had focus")

        // Back up: it moves on from where it stopped.
        remote.press(.up)
        XCTAssertTrue(wait(10) { hero.exists }, "the large entry did not get focus back")
        XCTAssertTrue(wait(5) { backdrop.value as? String == "moving" }, "the backdrop did not move again")
    }
}
