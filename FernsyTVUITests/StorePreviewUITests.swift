import XCTest

/// The App Store preview of the Apple TV app (store-media): a fixed walk through Start, Live TV
/// with its preview, a live channel with its strip and the guide, with the demo account in the
/// language of STORE_LANGUAGE (TEST_RUNNER_STORE_LANGUAGE). `scripts/store-media.sh previews`
/// records the simulator meanwhile and cuts the video at the activities "store preview start"
/// and "store preview end".
/// Skipped without STORE_LANGUAGE, so regular UI test runs leave it out.
final class StorePreviewUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    func testPreview() throws {
        guard let language = ProcessInfo.processInfo.environment["STORE_LANGUAGE"] else {
            throw XCTSkip("only for scripts/store-media.sh previews")
        }
        let app = launchDemo(arguments: ["-AppleLanguages", "(\(language))",
                                         "-AppleLocale", language == "de" ? "de_DE" : "en_US"])
        XCTAssertTrue(tabButton("Live TV", app).waitForExistence(timeout: 30), "no tabs:\n\(app.debugDescription)")
        // Start's rows and artwork.
        Thread.sleep(forTimeInterval: 5)

        // The marks the script cuts the recording at.
        XCTContext.runActivity(named: "store preview start") { _ in }
        // Every press waits for the app to settle (a second or more), so the walk stays short:
        // Start, Live TV's list with its preview, a channel with its strip, the guide.
        // STORE_CHANNEL_ROW: a channel in the middle of the demo film, not at its title cards;
        // it starts through the debug MCP server, which takes no time in the video.
        let row = Int(ProcessInfo.processInfo.environment["STORE_CHANNEL_ROW"] ?? "") ?? 0
        do {
            pause(2)
            press(.down, then: 1)
            press(.right, then: 0.5)

            focusFirstLiveChannel(app)
            pause(1.5)
            _ = mcpCall("play", #"{"item_id":"live:\#(101 + row)"}"#)
            pause(3.5)
            press(.down, then: 2)
            remote.press(.menu)
            _ = closePlayer(app)

            showLiveView("live.view.guide", app)
            press(.down, then: 0.5)
            press(.right, then: 1)
        }
        XCTContext.runActivity(named: "store preview end") { _ in }
    }

    /// Real time: the video shows each step for this long.
    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func press(_ button: XCUIRemote.Button, then seconds: TimeInterval) {
        remote.press(button)
        pause(seconds)
    }
}
