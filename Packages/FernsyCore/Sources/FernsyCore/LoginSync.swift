import CloudKit
import Foundation

/// Where synced logins are kept: the private CloudKit database; tests use a dictionary.
public protocol LoginBacking: Sendable {
    func save(_ payload: Data, as name: String) async throws
    func load(_ name: String) async throws -> Data?
    func isAvailable() async -> Bool
}

/// The provider and Jellyfin logins in the user's private CloudKit database, end-to-end
/// encrypted (icloud-sync design B: iCloud Keychain does not reach tvOS). Each device keeps its
/// own keychain copy and its own Jellyfin session; a device without an account offers what it
/// finds here. Signing out on one device leaves the synced login alone.
public final class LoginSync: Sendable {
    public static let enabledKey = "sync.logins"

    /// Server, user and password; never the session or the device id.
    public struct JellyfinLogin: Codable, Equatable, Sendable {
        public var server: String
        public var username: String
        public var password: String
        public init(server: String, username: String, password: String) {
            self.server = server
            self.username = username
            self.password = password
        }
    }

    private let backing: LoginBacking?
    nonisolated(unsafe) private let defaults: UserDefaults

    /// `backing` nil: logins are not synced in this run (tests, keychain-less runs).
    public init(backing: LoginBacking?, defaults: UserDefaults = .standard) {
        self.backing = backing
        self.defaults = defaults
    }

    /// The app's container: `iCloud.<bundle id>`, so debug builds use their own.
    public static func cloudKit() -> LoginSync {
        LoginSync(backing: CloudKitLogins(container: "iCloud." + (Bundle.main.bundleIdentifier ?? "de.mobilistics.fernsy")))
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    public func isAvailable() async -> Bool { await backing?.isAvailable() ?? false }

    /// Logins can be looked up at all: a backing (sync allowed) and "Zugangsdaten abgleichen" on.
    public var isActive: Bool { backing != nil && isEnabled }

    /// At launch without an account (icloud-auto-signin): what iCloud has, both kinds within
    /// `timeout`. Nothing past it, without iCloud or with the switch off; a login that arrives
    /// later is only offered.
    public func launchLogins(timeout: Duration = .seconds(10)) async -> (xtream: XtreamCredentials?, jellyfin: JellyfinLogin?) {
        guard isActive else { return (nil, nil) }
        return await withTaskGroup(of: (XtreamCredentials?, JellyfinLogin?)?.self) { group in
            group.addTask {
                guard await self.isAvailable() else { return (nil, nil) }
                async let xtream = self.xtream()
                async let jellyfin = self.jellyfin()
                return await (xtream, jellyfin)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            guard let first else {
                AppLog.warning(.app, "iCloud: no answer within \(timeout), the sign-in screen shows")
                return (nil, nil)
            }
            return first
        }
    }

    public func save(_ credentials: XtreamCredentials) async { await store(credentials, as: "xtream") }
    public func save(_ login: JellyfinLogin) async { await store(login, as: "jellyfin") }

    public func xtream() async -> XtreamCredentials? { await fetch(XtreamCredentials.self, "xtream") }
    public func jellyfin() async -> JellyfinLogin? { await fetch(JellyfinLogin.self, "jellyfin") }

    private func store<T: Encodable>(_ value: T, as name: String) async {
        guard let backing, isEnabled, let data = try? JSONEncoder().encode(value) else { return }
        do { try await backing.save(data, as: name) } catch {
            AppLog.warning(.app, "iCloud: could not save the \(name) login: \(error.localizedDescription)")
        }
    }

    private func fetch<T: Decodable>(_ type: T.Type, _ name: String) async -> T? {
        guard let backing, isEnabled else { return nil }
        do { return try await backing.load(name).flatMap { try? JSONDecoder().decode(type, from: $0) } } catch {
            AppLog.detail(.app, "iCloud: no \(name) login: \(error.localizedDescription)")
            return nil
        }
    }
}

/// One line of the launch screen while the apps sign in with the logins in iCloud
/// (icloud-auto-signin): what is being done, for which server, running or done.
public struct ICloudSignInStep: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case found, provider, channels, jellyfin }
    public let kind: Kind
    /// The server's host for `provider` and `jellyfin`.
    public var server: String
    public var done: Bool
    public var id: Kind { kind }

    public init(_ kind: Kind, server: String = "", done: Bool = false) {
        self.kind = kind
        self.server = server
        self.done = done
    }

    /// The launch screen stays at least this long once something signed in, so it does not flash.
    public static let minimumShown: Duration = .milliseconds(1500)
}

extension [ICloudSignInStep] {
    /// Marks `kind` done (adding it if missing), then adds `next` as running.
    public mutating func finish(_ kind: ICloudSignInStep.Kind, server: String = "", then next: ICloudSignInStep? = nil) {
        if let index = firstIndex(where: { $0.kind == kind }) { self[index].done = true } else { append(ICloudSignInStep(kind, server: server, done: true)) }
        if let next { append(next) }
    }
}

/// Logins in memory: debug builds' `IPTV_TESTICLOUDLOGIN`, so UI tests run the launch path
/// without iCloud.
public final class MemoryLogins: LoginBacking, @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [String: Data] = [:]
    /// How long a lookup takes, like CloudKit's 1–3 s on a real device.
    private let delay: Duration

    public init(xtream: XtreamCredentials? = nil, jellyfin: LoginSync.JellyfinLogin? = nil, delay: Duration = .zero) {
        self.delay = delay
        payloads["xtream"] = xtream.flatMap { try? JSONEncoder().encode($0) }
        payloads["jellyfin"] = jellyfin.flatMap { try? JSONEncoder().encode($0) }
    }

    public func save(_ payload: Data, as name: String) async throws { lock.withLock { payloads[name] = payload } }
    public func load(_ name: String) async throws -> Data? {
        try await Task.sleep(for: delay)
        return lock.withLock { payloads[name] }
    }
    public func isAvailable() async -> Bool { true }
}

/// Record type `Login`, one record per login (`xtream`, `jellyfin`), the JSON in
/// `encryptedValues["payload"]`.
struct CloudKitLogins: LoginBacking {
    let container: String

    private var database: CKDatabase { CKContainer(identifier: container).privateCloudDatabase }

    func save(_ payload: Data, as name: String) async throws {
        let record = CKRecord(recordType: "Login", recordID: CKRecord.ID(recordName: name))
        record.encryptedValues["payload"] = payload
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    func load(_ name: String) async throws -> Data? {
        do {
            return try await database.record(for: CKRecord.ID(recordName: name)).encryptedValues["payload"] as? Data
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func isAvailable() async -> Bool {
        (try? await CKContainer(identifier: container).accountStatus()) == .available
    }
}
