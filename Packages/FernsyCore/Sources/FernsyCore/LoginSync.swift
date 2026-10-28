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
