import XCTest

/// The Top Shelf (tvos-top-shelf 3.4) on the demo server: the app writes Continue Watching (a
/// film in progress) and the live row into its snapshot, and a Top Shelf link plays a channel.
final class TopShelfUITests: FernsyUITestCase {
    private func snapshot() -> [String: Any] {
        let text = mcpCall("top_shelf")
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let result = json["result"] as? [String: Any], let content = result["structuredContent"] as? [String: Any] else { return [:] }
        return content
    }

    private func items(_ kind: String, in snapshot: [String: Any]) -> [[String: Any]] {
        let sections = snapshot["sections"] as? [[String: Any]] ?? []
        return sections.first { $0["kind"] as? String == kind }?["items"] as? [[String: Any]] ?? []
    }

    func testSnapshotHasStartsRows() {
        let app = launchDemo(["IPTV_TESTRESUME": "movie.500:600:7080"])
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 30), "Start did not load")
        XCTAssertTrue(waitForLog("Top Shelf: ", timeout: 20), "no Top Shelf snapshot written")
        let shelf = snapshot()
        let resume = items("continueWatching", in: shelf)
        XCTAssertTrue(resume.contains { $0["id"] as? String == "movie:500" }, "movie 500 not in Continue Watching: \(shelf)")
        let sections = shelf["sections"] as? [[String: Any]] ?? []
        XCTAssertTrue(sections.contains { ($0["kind"] as? String ?? "").lowercased().contains("channels") && !(($0["items"] as? [Any]) ?? []).isEmpty },
                      "no live row: \(shelf)")
    }

    func testLinkPlaysAChannel() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 30), "Start did not load")
        XCUIDevice.shared.system.open(URL(string: "fernsy-dev://play?item=live:101")!)
        let state = app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(wait(30) { state.value as? String == "playing" }, "the link did not play channel 101:\n\(app.debugDescription)")
        XCTAssertTrue(waitForLog("play channel 101"), "not channel 101")
        _ = mcpCall("stop_playback")
    }
}

/// Looks at the Top Shelf itself (tvos-top-shelf 5.1): Fernsy Dev sits in the simulator's top row;
/// after the app wrote its snapshot, Home and focus on its icon show the shelf. Screenshots only.
final class TopShelfHomeUITests: FernsyUITestCase {
    func testHomeScreenShowsTheShelf() {
        let app = launchDemo(["IPTV_TESTRESUME": "movie.500:600:7080"])
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 30), "Start did not load")
        XCTAssertTrue(waitForLog("Top Shelf: ", timeout: 20), "no Top Shelf snapshot written")
        let remote = XCUIRemote.shared
        remote.press(.home)
        Thread.sleep(forTimeInterval: 3)
        let home = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")
        shot("home", home)
        // The top row: Settings, the TV-pattern app, Fernsy Dev.
        for _ in 0..<2 { remote.press(.right); Thread.sleep(forTimeInterval: 1) }
        Thread.sleep(forTimeInterval: 6)
        shot("top-shelf", home)
        remote.press(.left); Thread.sleep(forTimeInterval: 2)
        remote.press(.right); Thread.sleep(forTimeInterval: 6)
        shot("top-shelf-again", home)
    }
}
