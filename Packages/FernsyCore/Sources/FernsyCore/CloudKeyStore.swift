import CloudKit
import Foundation

/// Where the account key is shared between the user's devices: the private CloudKit database,
/// end-to-end encrypted (add-recording-cloud design A, like `LoginSync`); tests use a fake.
public protocol CloudKeyBacking: Sendable {
    /// nil only when iCloud says the record does not exist; any other failure throws.
    func load() async throws -> Data?
    /// Saves `payload` only if no key is stored yet; returns the key that is stored afterwards
    /// (the other one when another device won the race).
    func saveIfAbsent(_ payload: Data) async throws -> Data
    func isAvailable() async -> Bool
    /// The Mac marker (cloud-account-from-icloud-key design F): when a Mac last ran Fernsy
    /// with Fernsy Cloud; nil when no Mac ever wrote it, throws when iCloud cannot answer.
    func loadMacMarker() async throws -> Date?
    func saveMacMarker(_ date: Date) async throws
}

/// What iCloud says about the account key.
public enum CloudKeyLookup: Equatable, Sendable {
    case found(CloudAccountKey)
    /// No key exists for this Apple ID yet; a subscribing device may create it.
    case absent
    /// A key may exist but cannot be read now (iCloud off or failing); never create one then.
    case locked
}

/// Whether Fernsy on a Mac is known in the user's iCloud (design F).
public enum CloudMacPresence: Equatable, Sendable { case known, unknown, unavailable }

/// The account key for Fernsy Cloud: the device keychain first, then iCloud. Any device may
/// create it when subscribing (cloud-account-from-icloud-key design D), but only when iCloud
/// says that none exists: a second key would leave every upload unreadable.
public final class CloudKeyStore: Sendable {
    public static let keychainAccount = "cloud.key"

    private let backing: CloudKeyBacking?
    private let loadLocal: @Sendable () -> CloudAccountKey?
    private let saveLocal: @Sendable (CloudAccountKey) -> Void
    private let macOverride: CloudMacPresence?
    private let macMarkedAt: @Sendable () -> Date?
    private let setMacMarkedAt: @Sendable (Date) -> Void

    /// `backing` nil: the key lives only in the keychain (`IPTV_CLOUDKEY=local`, simulators).
    public init(backing: CloudKeyBacking?,
                loadLocal: @escaping @Sendable () -> CloudAccountKey? = { Keychain.load(CloudAccountKey.self, account: CloudKeyStore.keychainAccount) },
                saveLocal: @escaping @Sendable (CloudAccountKey) -> Void = { Keychain.save($0, account: CloudKeyStore.keychainAccount) },
                macOverride: CloudMacPresence? = nil,
                macMarkedAt: @escaping @Sendable () -> Date? = { UserDefaults.standard.object(forKey: "cloud.macMarkedAt") as? Date },
                setMacMarkedAt: @escaping @Sendable (Date) -> Void = { UserDefaults.standard.set($0, forKey: "cloud.macMarkedAt") }) {
        self.backing = backing
        self.loadLocal = loadLocal
        self.saveLocal = saveLocal
        self.macOverride = macOverride
        self.macMarkedAt = macMarkedAt
        self.setMacMarkedAt = setMacMarkedAt
    }

    /// The app's store: CloudKit container `iCloud.<bundle id>`. Debug switch `IPTV_CLOUDKEY`:
    /// `local` keeps the key in the keychain only (simulators have no iCloud), a base64 key JSON
    /// (`CloudAccountKey`) uses that key in memory, so UI tests read a fixture uploaded with it.
    /// `IPTV_CLOUDMAC=0|1` answers the Mac marker question without iCloud (default 1 without it).
    public static func live() -> CloudKeyStore {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let value = env["IPTV_CLOUDKEY"], !value.isEmpty {
            let mac: CloudMacPresence = env["IPTV_CLOUDMAC"] == "0" ? .unknown : .known
            if value == "local" { return CloudKeyStore(backing: nil, macOverride: mac) }
            let key = Data(base64Encoded: value).flatMap { try? JSONDecoder().decode(CloudAccountKey.self, from: $0) }
            return CloudKeyStore(backing: nil, loadLocal: { key }, saveLocal: { _ in }, macOverride: mac)
        }
        #endif
        return CloudKeyStore(backing: CloudKitKey(container: "iCloud." + (Bundle.main.bundleIdentifier ?? "de.mobilistics.fernsy")))
    }

    /// The key if this device has it or iCloud has it; nil means absent or locked.
    public func key() async -> CloudAccountKey? {
        if case .found(let key) = await lookup() { return key }
        return nil
    }

    /// The key, or why there is none. Only `unknownItem` from CloudKit counts as absent.
    public func lookup() async -> CloudKeyLookup {
        if let local = loadLocal() { return .found(local) }
        guard let backing else { return .absent }
        do {
            guard let data = try await backing.load() else { return .absent }
            guard let key = try? JSONDecoder().decode(CloudAccountKey.self, from: data) else { return .locked }
            saveLocal(key)
            AppLog.info(.app, "Fernsy Cloud: key \(key.id.prefix(8)) taken from iCloud")
            return .found(key)
        } catch {
            AppLog.warning(.app, "Fernsy Cloud: no key from iCloud: \(error.localizedDescription)")
            return .locked
        }
    }

    public struct Locked: Error {}

    /// Before subscribing or uploading: the existing key, or a new one stored in iCloud when
    /// iCloud says there is none. Throws `Locked` when iCloud cannot answer.
    public func createIfMissing() async throws -> CloudAccountKey {
        switch await lookup() {
        case .found(let existing): return existing
        case .locked: throw Locked()
        case .absent: break
        }
        let fresh = CloudAccountKey()
        guard let backing else {
            saveLocal(fresh)
            return fresh
        }
        let stored = try await backing.saveIfAbsent(try JSONEncoder().encode(fresh))
        let key = try JSONDecoder().decode(CloudAccountKey.self, from: stored)
        saveLocal(key)
        AppLog.info(.app, key == fresh ? "Fernsy Cloud: created key \(key.id.prefix(8))" : "Fernsy Cloud: another device created key \(key.id.prefix(8))")
        return key
    }

    public func isAvailable() async -> Bool { await backing?.isAvailable() ?? true }

    /// On the Mac at launch: notes in iCloud that Fernsy runs on a Mac, at most once a day.
    public func markMac(now: Date = .now) async {
        guard let backing, macOverride == nil else { return }
        if let last = macMarkedAt(), now.timeIntervalSince(last) < 86_400 { return }
        do {
            try await backing.saveMacMarker(now)
            setMacMarkedAt(now)
        } catch {
            AppLog.warning(.app, "Fernsy Cloud: Mac marker not saved: \(error.localizedDescription)")
        }
    }

    /// On iPad, iPhone and Apple TV before offering the subscription.
    public func macPresence() async -> CloudMacPresence {
        if let macOverride { return macOverride }
        guard let backing else { return .known }
        do {
            return try await backing.loadMacMarker() == nil ? .unknown : .known
        } catch {
            return .unavailable
        }
    }
}

/// Record type `CloudKey`, record name `cloud.key`, the key's JSON in `encryptedValues["key"]`.
struct CloudKitKey: CloudKeyBacking {
    let container: String
    private var database: CKDatabase { CKContainer(identifier: container).privateCloudDatabase }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: CloudKeyStore.keychainAccount) }

    func load() async throws -> Data? {
        do {
            return try await database.record(for: recordID).encryptedValues["key"] as? Data
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveIfAbsent(_ payload: Data) async throws -> Data {
        let record = CKRecord(recordType: "CloudKey", recordID: recordID)
        record.encryptedValues["key"] = payload
        do {
            // A new record with ifServerRecordUnchanged fails when one exists already.
            let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
            _ = try result.saveResults[recordID]?.get()
            return payload
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .partialFailure {
            if let stored = try await load() { return stored }
            throw error
        }
    }

    func isAvailable() async -> Bool {
        (try? await CKContainer(identifier: container).accountStatus()) == .available
    }

    /// Record type `CloudMac`, record name `cloud.mac`, plain field `seenAt`.
    private var macID: CKRecord.ID { CKRecord.ID(recordName: "cloud.mac") }

    func loadMacMarker() async throws -> Date? {
        do {
            return try await database.record(for: macID)["seenAt"] as? Date
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveMacMarker(_ date: Date) async throws {
        let record = CKRecord(recordType: "CloudMac", recordID: macID)
        record["seenAt"] = date
        // Last writer wins; the date only says that a Mac exists.
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        _ = try result.saveResults[macID]?.get()
    }
}
