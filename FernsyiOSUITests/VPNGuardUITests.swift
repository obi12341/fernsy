import XCTest

/// "IPTV only with VPN" on iPhone and iPad (vpn-guard 7.1, 7.3), on the demo server with the
/// VPN faked: `IPTV_TESTVPN` at launch and the debug tool `set_vpn` during the run.
final class VPNGuardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1", "IPTV_MCP": "1", "IPTV_MCPTOKEN": "test",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev", "IPTV_USER": "demo", "IPTV_PASS": "demo",
        ].merging(env) { $1 }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    private func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return condition()
    }

    /// A tool of the app's debug MCP server (port 52326).
    @discardableResult
    private func mcp(_ tool: String, _ arguments: String = "{}") -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:52326/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#.utf8)
        let done = DispatchSemaphore(value: 0)
        var text = "no answer"
        URLSession.shared.dataTask(with: request) { data, _, _ in
            text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no data"
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        return text
    }

    private func log(_ query: String) -> String { mcp("get_log", #"{"level":"detail","limit":500,"query":"\#(query)"}"#) }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 7.3: opened with the stored account and no VPN, the tabs show with the VPN note and nothing
    /// is asked of the provider; when the VPN connects, the channel list loads without input.
    func testOpensWithoutAVPNAndLoadsWhenItConnects() {
        // A first run with the VPN leaves the catalog in the cache, as on a device in use.
        var app = launch(["IPTV_TESTVPNGUARD": "1", "IPTV_TESTVPN": "on", "IPTV_TAB": "live"])
        XCTAssertTrue(wait(40) { self.log("signed in, ").contains("signed in, ") }, "no sign-in with the VPN")
        app.terminate()

        app = launch(["IPTV_TESTVPNGUARD": "1", "IPTV_TESTVPN": "off", "IPTV_TAB": "live"])
        XCTAssertTrue(element(app, "tabs").waitForExistence(timeout: 20), "no tabs without a VPN:\n\(app.debugDescription)")
        XCTAssertTrue(element(app, "vpn.note").waitForExistence(timeout: 20), "no VPN note:\n\(app.debugDescription)")
        XCTAssertFalse(element(app, "offline.note").exists, "the note blames the connection")
        XCTAssertTrue(wait(10) { self.log("vpn guard: provider request").contains("refused") }, "the sign-in was not refused")
        XCTAssertFalse(log("signed in, ").contains("signed in, "), "signed in without a VPN")
        shot("vpn-opened", app)

        mcp("set_vpn", #"{"on": true}"#)
        XCTAssertTrue(wait(30) { self.log("signed in, ").contains("signed in, ") }, "no sign-in after the VPN connected")
        XCTAssertTrue(wait(10) { !self.element(app, "vpn.note").exists }, "the VPN note stays")
        shot("vpn-connected", app)
    }

    /// 7.1: the setting is off at first, shows what Fernsy sees of a VPN, and stays on after a
    /// relaunch.
    func testTheSettingIsOffAtFirstAndStays() {
        var app = launch(["IPTV_TESTVPN": "off", "IPTV_TAB": "settings"])
        // Never left on for the tests after this one.
        addTeardownBlock { self.mcp("set_vpn", #"{"on": true, "guard": false}"#) }
        var toggle = openAccountSettings(app)
        XCTAssertEqual(toggle.value as? String, "0", "the setting is not off at first")
        let status = element(app, "settings.vpnStatus")
        XCTAssertTrue(wait(10) { status.value as? String == "not connected" }, "status: \(String(describing: status.value))")
        mcp("set_vpn", #"{"on": true}"#)
        XCTAssertTrue(wait(10) { status.value as? String == "connected" }, "the status does not follow the VPN")
        mcp("set_vpn", #"{"on": false}"#)
        XCTAssertTrue(wait(10) { status.value as? String == "not connected" }, "the status does not follow the VPN")

        toggle.switches.firstMatch.tap()
        XCTAssertTrue(wait(5) { toggle.value as? String == "1" }, "the tap did not switch the setting on")
        shot("vpn-setting-on", app)

        app.terminate()
        app = launch(["IPTV_TESTVPN": "off", "IPTV_TAB": "settings"])
        toggle = openAccountSettings(app)
        XCTAssertEqual(toggle.value as? String, "1", "the setting did not stay on")
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(wait(5) { toggle.value as? String == "0" }, "the tap did not switch the setting off")
    }

    /// Settings › the IPTV account, returning the setting's switch.
    private func openAccountSettings(_ app: XCUIApplication) -> XCUIElement {
        let account = element(app, "settings.account")
        // The iPhone has no Settings tab: it opens from Start.
        let fromStart = app.buttons["start.settings"]
        XCTAssertTrue(wait(30) { account.exists || fromStart.exists }, "neither Settings nor Start:\n\(app.debugDescription)")
        if !account.exists { fromStart.tap() }
        XCTAssertTrue(account.waitForExistence(timeout: 10), "no account row in Settings:\n\(app.debugDescription)")
        account.tap()
        let toggle = app.switches["settings.vpnGuard"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no VPN setting:\n\(app.debugDescription)")
        return toggle
    }
}
