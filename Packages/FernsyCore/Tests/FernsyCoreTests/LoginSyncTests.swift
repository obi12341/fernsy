import Foundation
import Testing
@testable import FernsyCore

/// Synced logins (icloud-sync 2.3): saved and found again, nothing while the switch is off.
struct LoginSyncTests {
    final class FakeLogins: LoginBacking, @unchecked Sendable {
        var records: [String: Data] = [:]
        func save(_ payload: Data, as name: String) async throws { records[name] = payload }
        func load(_ name: String) async throws -> Data? { records[name] }
        func isAvailable() async -> Bool { true }
    }

    @Test func loginsComeBack() async {
        let backing = FakeLogins()
        let sync = LoginSync(backing: backing, defaults: UserDefaults(suiteName: "LoginSyncTests.\(UUID())")!)
        let xtream = XtreamCredentials(server: "http://example.com:8080", username: "u", password: "p")
        await sync.save(xtream)
        await sync.save(LoginSync.JellyfinLogin(server: "http://nas:8096", username: "me", password: "pw"))
        #expect(await sync.xtream() == xtream)
        #expect(await sync.jellyfin()?.password == "pw")
        // The Jellyfin record holds no session.
        #expect(String(data: backing.records["jellyfin"]!, encoding: .utf8)?.contains("token") == false)
    }

    @Test func nothingWhileOff() async {
        let backing = FakeLogins()
        let sync = LoginSync(backing: backing, defaults: UserDefaults(suiteName: "LoginSyncTests.\(UUID())")!)
        sync.isEnabled = false
        await sync.save(XtreamCredentials(server: "http://x", username: "u", password: "p"))
        #expect(backing.records.isEmpty)
        #expect(await sync.xtream() == nil)
        #expect(await LoginSync(backing: nil).isAvailable() == false)
    }
}
