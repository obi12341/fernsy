import FernsyShared
import Foundation
import Testing
@testable import FernsyServer

struct LoginUpdateTests {
    let paired = Date(timeIntervalSince1970: 1_800_000_000)
    let login = XtreamCredentials(server: "https://tv.example", username: "anna", password: "new")

    @Test func onlyNewerLoginsCount() {
        let sent = ControlLogin(credentials: login, sentAt: paired + 60)
        #expect(LoginUpdate.isNew(sent, pairedAt: paired, lastDecided: nil))
        #expect(!LoginUpdate.isNew(sent, pairedAt: paired + 120, lastDecided: nil))   // from before this pairing
        #expect(!LoginUpdate.isNew(sent, pairedAt: paired, lastDecided: paired + 60))  // decided already
        #expect(LoginUpdate.isNew(sent, pairedAt: paired, lastDecided: paired + 30))
    }

    @Test func outcomes() {
        let sent = paired + 60
        #expect(LoginUpdate.outcome(.accepted, sentAt: sent, waitingSince: sent, now: sent)?.result == .accepted)
        #expect(LoginUpdate.outcome(.refused, sentAt: sent, waitingSince: sent, now: sent)?.result == .refused)
        // Unreachable: tried again for an hour, then given up.
        #expect(LoginUpdate.outcome(.unreachable, sentAt: sent, waitingSince: sent, now: sent + 600) == nil)
        #expect(LoginUpdate.outcome(.unreachable, sentAt: sent, waitingSince: sent, now: sent + 3600)?.result == .unreachable)
    }
}
