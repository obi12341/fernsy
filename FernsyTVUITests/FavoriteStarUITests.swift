import XCTest

/// The favourite button of a film page (fix/tv-favorite-star-focus): its star set its own color,
/// so on the focused button's white pill it was light on white (not to be seen) or gold on white.
/// With focus the star is dark like every button's content, and the filled star says that it is a
/// favourite; without focus a favourite's star is gold.
final class FavoriteStarUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    /// The pixels in the middle of `element` (a square of `side` points, where the star is): how
    /// many are dark and how many gold.
    private func starPixels(_ element: XCUIElement, side: CGFloat = 44) -> (dark: Int, gold: Int) {
        let image = XCUIScreen.main.screenshot().image
        let scale = image.scale, frame = element.frame
        let crop = CGRect(x: (frame.midX - side / 2) * scale, y: (frame.midY - side / 2) * scale, width: side * scale, height: side * scale)
        guard let part = image.cgImage?.cropping(to: crop), let data = part.dataProvider?.data as Data? else { return (0, 0) }
        let step = part.bitsPerPixel / 8
        var dark = 0, gold = 0
        for y in 0..<part.height {
            for x in 0..<part.width {
                let at = y * part.bytesPerRow + x * step
                guard at + 2 < data.count else { continue }
                // Red and blue may be either way round in the screenshot's bytes.
                let a = Int(data[at]), green = Int(data[at + 1]), b = Int(data[at + 2])
                if a < 90 && green < 90 && b < 90 { dark += 1 }
                if max(a, b) > 220 && min(a, b) < 130 && (150...235).contains(green) { gold += 1 }
            }
        }
        return (dark, gold)
    }

    func testTheStarShowsOnTheFocusedButton() {
        let app = launchDemo(["IPTV_OPEN": "fernsy-dev://open?item=movie:500"])
        let favorite = app.buttons["film.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 30), "no film page:\n\(app.debugDescription)")
        let play = app.buttons["film.play"]
        if !wait(5, { play.hasFocus || favorite.hasFocus }) { remote.press(.down) }
        for _ in 0..<4 where !favorite.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(favorite.hasFocus, "the favourite button has no focus:\n\(app.debugDescription)")
        XCTAssertNotEqual(favorite.value as? String, "favorite", "the film is a favourite already")

        // Not a favourite, with focus: a dark outline on the white button.
        Thread.sleep(forTimeInterval: 1)
        let outline = starPixels(favorite)
        shot("favorite-focused", app)
        XCTAssertGreaterThan(outline.dark, 50, "the star does not show on the focused button")

        // A favourite, with focus: the star is filled and still dark, not gold on white.
        remote.press(.select)
        XCTAssertTrue(wait(5) { favorite.value as? String == "favorite" }, "the click did not make the film a favourite")
        Thread.sleep(forTimeInterval: 1)
        let filled = starPixels(favorite)
        shot("favorite-focused-filled", app)
        XCTAssertGreaterThan(filled.dark, outline.dark, "the favourite's star is not filled dark on the focused button")
        XCTAssertLessThan(filled.gold, 20, "the favourite's star is gold on the focused button")

        // Focus elsewhere: the favourite's star is gold.
        remote.press(.left)
        XCTAssertTrue(wait(3) { !favorite.hasFocus }, "Left did not leave the favourite button")
        Thread.sleep(forTimeInterval: 1)
        let resting = starPixels(favorite)
        shot("favorite-resting", app)
        XCTAssertGreaterThan(resting.gold, 50, "the favourite's star is not gold without focus")
    }
}
