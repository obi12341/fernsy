import XCTest

/// "IPTV only with VPN" on the Apple TV (vpn-guard 7.1, 7.2), on the demo server with the VPN
/// faked: `IPTV_TESTVPN` at launch and the debug tool `set_vpn` during the run.
final class VPNGuardUITests: FernsyUITestCase {
    private let remote = XCUIRemote.shared

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func expectStatus(_ kind: String, _ app: XCUIApplication, timeout: TimeInterval = 30) {
        let status = element("player.status", app)
        XCTAssertTrue(wait(timeout) { status.exists && status.value as? String == kind },
                      "the status did not show \(kind) (now \(String(describing: status.value))):\n\(app.debugDescription)")
    }

    /// Connections to the provider's streams the app has made so far (first ones and reconnects).
    private func streamConnections() -> Int { appLog("connected (HTTP").count }

    /// 7.2: nothing goes to the provider without a VPN – not at launch, not when a channel is
    /// started, not for a channel that runs – and everything goes on by itself with the VPN.
    func testNothingGoesToTheProviderWithoutAVPN() {
        let app = launchDemo(["IPTV_TESTVPNGUARD": "1", "IPTV_TESTVPN": "off"])
        let note = element("vpn.note", app)
        XCTAssertTrue(note.waitForExistence(timeout: 30), "no VPN note at launch:\n\(app.debugDescription)")
        XCTAssertTrue(waitForLog("vpn guard: provider request account refused"), "the sign-in was not refused")
        XCTAssertTrue(appLog("signed in, ").isEmpty, "signed in without a VPN")
        shot("vpn-launch", app)

        // The VPN connects: the app signs in and loads by itself.
        _ = mcpCall("set_vpn", #"{"on": true}"#)
        XCTAssertTrue(waitForLog("signed in, ", timeout: 30), "no sign-in after the VPN connected")
        XCTAssertTrue(wait(10) { !note.exists }, "the VPN note stays")
        XCTAssertTrue(waitForLog(" films, ", timeout: 30), "the catalog did not load")

        // Starting a channel without a VPN: refused with the reason, no connection.
        _ = mcpCall("set_vpn", #"{"on": false}"#)
        _ = mcpCall("play", #"{"item_id": "live:101"}"#)
        expectStatus("failed", app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'No VPN connection'")).firstMatch.exists,
                      "the failure does not name the VPN:\n\(app.debugDescription)")
        XCTAssertEqual(streamConnections(), 0, "a stream was opened without a VPN")
        shot("vpn-refused", app)

        // With the VPN, Try Again plays.
        _ = mcpCall("set_vpn", #"{"on": true}"#)
        let retry = app.buttons["player.status.retry"]
        XCTAssertTrue(wait(5) { retry.hasFocus }, "Try Again has no focus")
        remote.press(.select)
        XCTAssertTrue(waitFor(element("player.state", app), value: "playing", timeout: 40), "the channel does not play with the VPN")
        expectStatus("none", app, timeout: 10)

        // The VPN drops while the channel plays: the card names it, and nothing is requested.
        _ = mcpCall("set_vpn", #"{"on": false}"#)
        XCTAssertTrue(waitForLog("the stream waits for it", timeout: 10), "the stream did not stop for the missing VPN")
        let before = streamConnections()
        expectStatus("vpn", app, timeout: 90)
        XCTAssertTrue(app.staticTexts["VPN is not connected"].exists, "no VPN text:\n\(app.debugDescription)")
        shot("vpn-waiting", app)
        Thread.sleep(forTimeInterval: 8)
        XCTAssertEqual(streamConnections(), before, "the stream reconnected without a VPN")
        expectStatus("vpn", app, timeout: 1)

        // The VPN is back: the channel plays again without input.
        _ = mcpCall("set_vpn", #"{"on": true}"#)
        XCTAssertTrue(waitForLog("the VPN is back", timeout: 10), "the stream did not notice the VPN")
        XCTAssertTrue(waitFor(element("player.state", app), value: "playing", timeout: 60), "the channel did not go on")
        expectStatus("none", app, timeout: 20)
        XCTAssertGreaterThan(streamConnections(), before, "no new connection after the VPN came back")
    }

    /// 4.1: artwork is not downloaded without a VPN; what shows afterwards loads with it.
    func testArtworkWaitsForTheVPN() {
        // Settings shows no artwork: nothing is loaded before the VPN goes.
        let app = launchDemo(["IPTV_TESTVPNGUARD": "1", "IPTV_TESTVPN": "on", "IPTV_FRESHIMAGES": "1", "IPTV_TAB": "settings"])
        XCTAssertTrue(waitForLog(" films, ", timeout: 40), "the catalog did not load")
        _ = mcpCall("set_vpn", #"{"on": false}"#)
        let before = appLog("image loaded").count
        showTab("Movies", app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.movie.' OR identifier BEGINSWITH 'movie.'")).firstMatch.waitForExistence(timeout: 15),
                      "no films:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 4)
        XCTAssertEqual(appLog("image loaded").count, before, "artwork was downloaded without a VPN")
        shot("vpn-artwork-held", app)

        _ = mcpCall("set_vpn", #"{"on": true}"#)
        showTab("Series", app)
        XCTAssertTrue(wait(20) { self.appLog("image loaded").count > before }, "no artwork with the VPN")
    }

    /// 7.1: the setting is off at first, shows what Fernsy sees of a VPN, and stays on after a
    /// relaunch.
    func testTheSettingIsOffAtFirstAndStays() {
        var app = launchDemo(["IPTV_TESTVPN": "off"])
        // Never left on for the tests after this one.
        addTeardownBlock { _ = self.mcpCall("set_vpn", #"{"on": true, "guard": false}"#) }
        let toggle = openAccountSettings(app)
        XCTAssertEqual(toggle.value as? String, "off", "the setting is not off at first")
        let status = element("settings.vpnStatus", app)
        XCTAssertTrue(waitFor(status, value: "not connected"), "status: \(String(describing: status.value))")
        _ = mcpCall("set_vpn", #"{"on": true}"#)
        XCTAssertTrue(waitFor(status, value: "connected"), "the status does not follow the VPN")
        _ = mcpCall("set_vpn", #"{"on": false}"#)
        XCTAssertTrue(waitFor(status, value: "not connected"), "the status does not follow the VPN")

        focus(toggle, in: app, moves: [.down])
        remote.press(.select)
        XCTAssertTrue(waitFor(toggle, value: "on"), "the click did not switch the setting on")
        shot("vpn-setting-on", app)
        XCTAssertTrue(element("vpn.note", app).waitForExistence(timeout: 5), "no VPN note with the setting on and no VPN")

        app.terminate()
        app = launchDemo(["IPTV_TESTVPN": "off"])
        let again = openAccountSettings(app)
        XCTAssertEqual(again.value as? String, "on", "the setting did not stay on")
        focus(again, in: app, moves: [.down])
        remote.press(.select)
        XCTAssertTrue(waitFor(again, value: "off"), "the click did not switch the setting off")
    }

    /// Settings › IPTV Account, returning the setting's row.
    private func openAccountSettings(_ app: XCUIApplication) -> XCUIElement {
        showTab("Settings", app)
        let account = app.buttons["settings.account"]
        focus(account, in: app, moves: [.down])
        remote.press(.select)
        let toggle = app.buttons["settings.vpnGuard"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no VPN setting:\n\(app.debugDescription)")
        return toggle
    }
}
