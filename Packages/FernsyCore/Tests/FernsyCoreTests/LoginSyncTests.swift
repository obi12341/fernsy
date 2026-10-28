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

    /// icloud-auto-signin: the launch lookup returns both kinds, and nothing past its limit.
    @Test func launchLoginsWithinTheLimit() async {
        let defaults = UserDefaults(suiteName: "LoginSyncTests.\(UUID())")!
        let xtream = XtreamCredentials(server: "http://example.com:8080", username: "u", password: "p")
        let found = await LoginSync(backing: MemoryLogins(xtream: xtream), defaults: defaults).launchLogins()
        #expect(found.xtream == xtream)
        #expect(found.jellyfin == nil)
        let late = await LoginSync(backing: SlowLogins(), defaults: defaults).launchLogins(timeout: .milliseconds(100))
        #expect(late.xtream == nil)
        let off = LoginSync(backing: MemoryLogins(xtream: xtream), defaults: defaults)
        off.isEnabled = false
        #expect(await off.launchLogins().xtream == nil)
    }

    final class SlowLogins: LoginBacking, @unchecked Sendable {
        func save(_ payload: Data, as name: String) async throws {}
        func load(_ name: String) async throws -> Data? {
            try await Task.sleep(for: .seconds(5))
            return try JSONEncoder().encode(XtreamCredentials(server: "http://late", username: "u", password: "p"))
        }
        func isAvailable() async -> Bool { true }
    }
}
