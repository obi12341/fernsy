import CloudKit
import Foundation

/// Where the control key is shared between the user's devices (headless-recorder design 3):
/// the private CloudKit database, end-to-end encrypted, like the cloud key; tests use a fake.
public protocol ControlKeyBacking: Sendable {
    /// nil only when iCloud says the record does not exist; any other failure throws.
    func load() async throws -> Data?
    /// Saves `payload` only if no key is stored yet; returns the key stored afterwards.
    func saveIfAbsent(_ payload: Data) async throws -> Data
}

/// The control key: the device keychain first, then iCloud. Created when the user pairs a
/// Fernsy Server, only when iCloud says none exists, so every device ends up with the same one.
public final class ControlKeyStore: Sendable {
    public static let keychainAccount = "control.key"

    private let backing: ControlKeyBacking?
    private let loadLocal: @Sendable () -> ControlKey?
    private let saveLocal: @Sendable (ControlKey) -> Void

    public init(backing: ControlKeyBacking?,
                loadLocal: @escaping @Sendable () -> ControlKey? = { Keychain.load(ControlKey.self, account: ControlKeyStore.keychainAccount) },
                saveLocal: @escaping @Sendable (ControlKey) -> Void = { Keychain.save($0, account: ControlKeyStore.keychainAccount) }) {
        self.backing = backing
        self.loadLocal = loadLocal
        self.saveLocal = saveLocal
    }

    /// The app's store: CloudKit container `iCloud.<bundle id>`. Debug switch `IPTV_CONTROLKEY`:
    /// `local` keeps the key in the keychain only (simulators), a base64 key JSON uses that key.
    public static func live() -> ControlKeyStore {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["IPTV_CONTROLKEY"], !value.isEmpty {
            if value == "local" { return ControlKeyStore(backing: nil) }
            let key = Data(base64Encoded: value).flatMap { try? JSONDecoder().decode(ControlKey.self, from: $0) }
            return ControlKeyStore(backing: nil, loadLocal: { key }, saveLocal: { _ in })
        }
        #endif
        return ControlKeyStore(backing: CloudKitControlKey(container: "iCloud." + (Bundle.main.bundleIdentifier ?? "de.mobilistics.fernsy")))
    }

    public struct Locked: Error {}

    /// The key if this device or iCloud has it; nil when there is none (yet) or iCloud cannot say.
    public func key() async -> ControlKey? {
        if let local = loadLocal() { return local }
        guard let backing, let data = try? await backing.load(), let key = try? JSONDecoder().decode(ControlKey.self, from: data) else { return nil }
        saveLocal(key)
        return key
    }

    /// When pairing: the existing key, or a new one stored in iCloud. Throws `Locked` when iCloud
    /// cannot answer (a second key would split the user's devices).
    public func createIfMissing() async throws -> ControlKey {
        if let local = loadLocal() { return local }
        guard let backing else {
            let fresh = ControlKey()
            saveLocal(fresh)
            return fresh
        }
        let existing: Data?
        do { existing = try await backing.load() } catch { throw Locked() }
        if let existing, let key = try? JSONDecoder().decode(ControlKey.self, from: existing) {
            saveLocal(key)
            return key
        }
        let stored = try await backing.saveIfAbsent(try JSONEncoder().encode(ControlKey()))
        let key = try JSONDecoder().decode(ControlKey.self, from: stored)
        saveLocal(key)
        return key
    }
}

/// Record type `ControlKey`, record name `control.key`, the key's JSON in `encryptedValues["key"]`.
struct CloudKitControlKey: ControlKeyBacking {
    let container: String
    private var database: CKDatabase { CKContainer(identifier: container).privateCloudDatabase }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: ControlKeyStore.keychainAccount) }

    func load() async throws -> Data? {
        do {
            return try await database.record(for: recordID).encryptedValues["key"] as? Data
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveIfAbsent(_ payload: Data) async throws -> Data {
        let record = CKRecord(recordType: "ControlKey", recordID: recordID)
        record.encryptedValues["key"] = payload
        do {
            let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
            _ = try result.saveResults[recordID]?.get()
            return payload
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .partialFailure {
            if let stored = try await load() { return stored }
            throw error
        }
    }
}
