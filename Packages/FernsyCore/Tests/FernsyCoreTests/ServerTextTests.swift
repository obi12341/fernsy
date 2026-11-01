import Foundation
import Testing
@testable import FernsyCore
@testable import FernsyShared

/// The login notes of server-login-update in the server's settings.
struct ServerTextTests {
    let sent = Date(timeIntervalSince1970: 1_800_000_000)

    func status(refused: Bool = false, result: ControlLoginOutcome.Result? = nil) -> ControlServerStatus {
        ControlServerStatus(lastContact: sent, version: "1", login: "demo @ tv.example", loginRefused: refused,
                            loginUpdate: result.map { ControlLoginOutcome(sentAt: sent, result: $0) })
    }

    @Test func notes() {
        #expect(ServerText.loginNote(status(), checking: false) == nil)
        #expect(ServerText.loginNote(status(result: .accepted), checking: false) == nil)
        #expect(ServerText.loginNote(status(), checking: true) != nil)
        #expect(!ServerText.loginNoteIsWarning(status(), checking: true))
        for warning in [status(result: .refused), status(result: .unreachable), status(refused: true)] {
            #expect(ServerText.loginNote(warning, checking: false) != nil)
            #expect(ServerText.loginNoteIsWarning(warning, checking: false))
        }
        // A refused login of the server itself wins over an older accepted update.
        #expect(ServerText.loginNote(status(refused: true, result: .accepted), checking: false)?.contains("refuses") == true)
    }
}
