import XCTest

/// The player's status in the middle of the screen (tvos-player-status 3.1–3.5), each case
/// produced on the demo server with the player's test switches.
final class PlayerStatusUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func status(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["player.status"] }

    /// Waits until the status layer shows `kind`, failing with the element tree otherwise.
    private func expect(_ kind: String, _ app: XCUIApplication, timeout: TimeInterval = 30) {
        let element = status(app)
        XCTAssertTrue(wait(timeout) { element.exists && element.value as? String == kind },
                      "the status did not show \(kind) (now \(String(describing: element.value))):\n\(app.debugDescription)")
    }

    private func loadingText(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Loading '")).firstMatch
    }

    /// 3.1: a slow provider (IPTV_TESTSLOWSTART=3) – the channel's logo, a spinner and "Loading …"
    /// until its picture, at launch and when zapping from the strip.
    func testLoadingWhileSwitchingChannels() {
        let app = launchDemo(["IPTV_TESTSLOWSTART": "3", "IPTV_AUTOPLAY": "live:101"])
        expect("loading", app)
        XCTAssertTrue(loadingText(app).exists, "no loading text:\n\(app.debugDescription)")
        shot("status-loading", app)
        expect("none", app)
        XCTAssertEqual(app.descendants(matching: .any)["player.state"].value as? String, "playing")

        remote.press(.down)
        let strip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strip.'"))
        XCTAssertTrue(strip.firstMatch.waitForExistence(timeout: 5), "no channel strip")
        remote.press(.select)
        expect("loading", app, timeout: 10)
        XCTAssertTrue(loadingText(app).exists, "no loading text when zapping")
        shot("status-zapping", app)
        expect("none", app)
    }

    /// 3.2: a channel that sends nothing (IPTV_TESTNODATA=silent:30) – the player restarts the
    /// stream and says so with the attempt, then plays once data comes.
    func testReconnectingWithAttempts() {
        let app = launchDemo(["IPTV_TESTNODATA": "silent:30", "IPTV_AUTOPLAY": "live:101"])
        expect("reconnecting", app, timeout: 40)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Attempt '")).firstMatch.waitForExistence(timeout: 20),
                      "no attempt number:\n\(app.debugDescription)")
        shot("status-reconnecting", app)
        XCTAssertTrue(wait(90) { app.descendants(matching: .any)["player.state"].value as? String == "playing" }, "playback did not continue")
        expect("none", app, timeout: 10)
    }

    /// 3.3: a channel that trickles (IPTV_TESTNET=trickle, IPTV_TRICKLEMORE=all) runs dry – the
    /// card blames the provider.
    func testStallBlamesTheProvider() {
        let app = launchDemo(["IPTV_TESTNET": "trickle:8", "IPTV_TRICKLEMORE": "all", "IPTV_TRICKLEKBIT": "100", "IPTV_AUTOPLAY": "live:101"])
        expect("stall", app, timeout: 90)
        XCTAssertTrue(app.staticTexts["The channel arrives too slowly from the provider"].exists, "no provider text:\n\(app.debugDescription)")
        shot("status-stall-provider", app)
    }

    /// 3.3: the same stall without network (IPTV_TESTNOPATH=1) – the card names the network.
    func testStallWithoutNetwork() {
        let app = launchDemo(["IPTV_TESTNET": "trickle:8", "IPTV_TRICKLEMORE": "all", "IPTV_TRICKLEKBIT": "100",
                              "IPTV_TESTNOPATH": "1", "IPTV_AUTOPLAY": "live:101"])
        expect("stall", app, timeout: 90)
        XCTAssertTrue(app.staticTexts["No internet connection"].exists, "no network text:\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["The channel arrives too slowly from the provider"].exists, "the provider is blamed without network")
        shot("status-stall-network", app)
    }

    /// 3.4: offline channels (IPTV_TESTNODATA=offline:25) – the card explains it; "Next Channel"
    /// is reachable with the remote and tunes the next channel; "Try Again" plays once it is back.
    func testOfflineChannelOffersRetryAndNext() {
        let app = launchDemo(["IPTV_TESTNODATA": "offline:25", "IPTV_AUTOPLAY": "live:101"])
        let started = Date()
        expect("offline", app)
        XCTAssertTrue(app.staticTexts["Channel is offline at the provider"].exists, "no offline text:\n\(app.debugDescription)")
        let retry = app.buttons["player.status.retry"], next = app.buttons["player.status.next"]
        XCTAssertTrue(wait(5) { retry.hasFocus }, "Try Again has no focus:\n\(app.debugDescription)")
        shot("status-offline", app)

        remote.press(.right)
        XCTAssertTrue(wait(5) { next.hasFocus }, "Next Channel has no focus")
        remote.press(.select)
        XCTAssertTrue(wait(10) { !self.mcpCall("now_playing").contains("live:101") }, "Next Channel did not tune another channel")
        // Still inside the offline window: the next channel fails the same way.
        expect("offline", app)

        // After the window, Try Again plays.
        let left = 26 - Date().timeIntervalSince(started)
        if left > 0 { Thread.sleep(forTimeInterval: left) }
        // A button of the card has focus (staying on "Next Channel" lets the user zap on).
        XCTAssertTrue(wait(5) { retry.hasFocus || next.hasFocus }, "no button of the next channel's card has focus:\n\(app.debugDescription)")
        if !retry.hasFocus { remote.press(.left) }
        XCTAssertTrue(wait(5) { retry.hasFocus }, "Try Again cannot be reached with the remote")
        remote.press(.select)
        XCTAssertTrue(wait(30) { app.descendants(matching: .any)["player.state"].value as? String == "playing" }, "Try Again did not play")
        expect("none", app, timeout: 10)
    }

    /// 3.5: a film with a slow provider (IPTV_TESTSLOWSTART=3) shows its title while loading; Live
    /// TV's preview pane shows its spinner while the channel loads.
    func testFilmLoadingAndPreviewSpinner() {
        let app = launchDemo(["IPTV_TESTSLOWSTART": "3"])
        XCTAssertTrue(app.buttons["start.hero.resume"].waitForExistence(timeout: 30), "Start did not load")
        _ = mcpCall("play_item", #"{"item_id":"movie:500","from_start":true}"#)
        expect("loading", app, timeout: 10)
        XCTAssertTrue(app.staticTexts["Loading Stardust…"].exists, "no film title while loading:\n\(app.debugDescription)")
        shot("status-film-loading", app)
        expect("none", app)
        remote.press(.menu)
        XCTAssertTrue(wait(10) { !self.status(app).exists }, "the player did not close")

        let preview = app.descendants(matching: .any)["live.preview.status"]
        focusFirstLiveChannel(app)
        XCTAssertTrue(wait(15) { preview.exists && preview.value as? String == "loading" }, "no spinner in the preview:\n\(app.debugDescription)")
        shot("status-preview-loading", app)
        XCTAssertTrue(wait(30) { preview.value as? String == "none" }, "the preview's spinner stayed")
    }
}
