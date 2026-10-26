import XCTest

/// The Apple TV app with the Siri Remote, against the demo server: to a channel, select, it
/// plays, Back returns to the list with that channel focused. Uses the placeholder screens'
/// identifiers (`channel.<id>`, `player.state`), which the designed screens keep.
final class ChannelPlaybackUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSelectChannelPlaysAndBackReturnsToList() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FERNSY_NO_KEYCHAIN": "1",
            "IPTV_SERVER": "https://fernsy-demo.mobilistics.workers.dev",
            "IPTV_USER": "demo",
            "IPTV_PASS": "demo",
        ]
        app.launch()
        let remote = XCUIRemote.shared

        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30), "the channel list did not appear")
        remote.press(.down)
        // The focused element: SwiftUI may report a list row as a cell or as a button.
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "nothing has focus:\n\(app.debugDescription)")
        let channel = Self.channelIdentifier(of: focused)
        XCTAssertNotNil(channel, "focus is not on a channel:\n\(app.debugDescription)")

        remote.press(.select)
        let state = app.otherElements["player.state"].exists ? app.otherElements["player.state"] : app.descendants(matching: .any)["player.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 15), "the player did not open")
        let playing = NSPredicate(format: "value == 'playing'")
        expectation(for: playing, evaluatedWith: state)
        waitForExpectations(timeout: 30)

        remote.press(.menu)
        let row = app.descendants(matching: .any)[channel!]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the list did not come back")
        let deadline = Date().addingTimeInterval(10)
        var back: String?
        while Date() < deadline {
            back = Self.channelIdentifier(of: focused)
            if back == channel { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(back, channel, "a different element has focus after Back")
    }

    /// `channel.<id>` of the element or of the first element inside it that carries one.
    private static func channelIdentifier(of element: XCUIElement) -> String? {
        if element.identifier.hasPrefix("channel.") { return element.identifier }
        let inner = element.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'channel.'")).firstMatch
        return inner.exists ? inner.identifier : nil
    }
}
