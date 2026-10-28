import CryptoKit
import Foundation

/// What the iCloud key-value store offers (`NSUbiquitousKeyValueStore`); tests use a dictionary.
public protocol SyncBacking: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SyncBacking {}

/// iCloud sync of settings and per-account choices between the user's Macs and Apple TVs
/// (icloud-sync design A). The local values stay what the apps read; this mirrors them:
///
/// - UserDefaults keys (favourites, recently watched, track languages, padding) as one entry
///   each, `d.<key>` = `{v: value, t: date}`; a local change is noticed through
///   `UserDefaults.didChangeNotification` and stamped "now".
/// - Resume positions and watched marks (ResumeStore's `resume.*` and `watched.*` keys) as one
///   entry `resume`, merged per item by its date, so two devices never undo each other's
///   progress; entries older than 90 days stay local.
/// - Codable values with their own `modifiedAt` (visibility, pinned categories), per account:
///   `push` and `pull`.
///
/// Per value the newer change wins. Nothing is sent or applied while `isEnabled` is off, and the
/// app keeps working without iCloud: the backing then only keeps the values on this device.
@MainActor
public final class SyncStore {
    public static let enabledKey = "sync.enabled"

    private let backing: SyncBacking?
    private let defaults: UserDefaults
    private let keys: [String]
    private var snapshot: [String: Any] = [:]
    private var resumeSnapshot: [String: ResumeEntry] = [:]
    private var observers: [NSObjectProtocol] = []
    private var applying = false
    /// After each look at the remote values, with the names (`d.<key>`, `resume`) that came
    /// from another device; the app then also pulls its Codable values again.
    public var onChange: ((Set<String>) -> Void)?
    private var pushScheduled = false

    /// `backing` nil: sync is off for this run (UI tests, keychain-less runs).
    public init(backing: SyncBacking?, defaults: UserDefaults = .standard, keys: [String]) {
        self.backing = backing
        self.defaults = defaults
        self.keys = keys
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey); if newValue { pullAll(); pushLocalChanges() } }
    }

    /// Takes newer remote values, sends local ones the other devices lack, and from then on
    /// follows changes on both sides.
    public func start(notifications: NotificationCenter = .default) {
        takeSnapshot()
        backing?.synchronize()
        pullAll()
        pushLocalChanges()
        observers.append(notifications.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePush() }
        })
        if let store = backing as? NSUbiquitousKeyValueStore {
            observers.append(notifications.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pullAll() }
            })
        }
    }

    // MARK: Codable values with their own date

    /// Sends `value` changed at `modifiedAt` under `name` (see `accountName`).
    public func push<T: Encodable>(_ value: T, as name: String, modifiedAt: Date) {
        guard let backing, isEnabled, let data = try? JSONEncoder().encode(value) else { return }
        backing.set(["v": data, "t": modifiedAt, "version": 1] as [String: Any], forKey: name)
    }

    /// The value under `name` if another device changed it after `localModifiedAt`.
    public func pull<T: Decodable>(_ type: T.Type, name: String, newerThan localModifiedAt: Date) -> T? {
        guard let backing, isEnabled, let entry = backing.object(forKey: name) as? [String: Any],
              (entry["version"] as? Int ?? 1) <= 1, let date = entry["t"] as? Date, date > localModifiedAt,
              let data = entry["v"] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// A short name for a per-account value: keys of the store are limited to 64 bytes and
    /// account keys contain the server address.
    public static func accountName(_ accountKey: String, _ value: String) -> String {
        let digest = SHA256.hash(data: Data(accountKey.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "a.\(digest).\(value)"
    }

    // MARK: UserDefaults keys and resume positions

    private func takeSnapshot() {
        for key in keys { snapshot[key] = defaults.object(forKey: key) }
        resumeSnapshot = ResumeEntry.read(defaults)
    }

    /// Playback saves its position every few seconds: changes are sent at most every 2 s.
    private func schedulePush() {
        guard !applying, !pushScheduled else { return }
        pushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            pushScheduled = false
            pushLocalChanges()
        }
    }

    /// Local changes since the last look: stamped now and sent.
    func pushLocalChanges() {
        guard !applying, let backing, isEnabled else { return }
        for key in keys {
            let value = defaults.object(forKey: key)
            let stamp = "sync.t." + key
            // A value from before sync existed counts as changed now, once.
            let unsent = defaults.object(forKey: stamp) == nil && value != nil
            guard unsent || !Self.equal(value, snapshot[key]) else { continue }
            snapshot[key] = value
            let now = Date()
            applyingDefaults { defaults.set(now, forKey: stamp) }
            backing.set(value.map { ["v": $0, "t": now] as [String: Any] } ?? ["t": now], forKey: "d." + key)
        }
        let resume = ResumeEntry.read(defaults)
        if resume != resumeSnapshot || backing.object(forKey: "resume") == nil && !resume.isEmpty {
            resumeSnapshot = resume
            let remote = ResumeEntry.decode(backing.object(forKey: "resume"))
            let merged = ResumeEntry.merge(remote, resume.filter { $0.value.at > Date().addingTimeInterval(-90 * 86400) })
            backing.set(ResumeEntry.encode(merged), forKey: "resume")
        }
    }

    /// Remote values newer than the local ones: written to UserDefaults, named in `onChange`.
    func pullAll() {
        guard let backing, isEnabled else { return }
        var changed: Set<String> = []
        for key in keys {
            guard let entry = backing.object(forKey: "d." + key) as? [String: Any], let date = entry["t"] as? Date else { continue }
            let local = defaults.object(forKey: "sync.t." + key) as? Date ?? .distantPast
            guard date > local else { continue }
            let value = entry["v"]
            applyingDefaults {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
                defaults.set(date, forKey: "sync.t." + key)
            }
            snapshot[key] = value
            changed.insert("d." + key)
        }
        let remote = ResumeEntry.decode(backing.object(forKey: "resume"))
        let local = ResumeEntry.read(defaults)
        let merged = ResumeEntry.merge(local, remote)
        if merged != local {
            applyingDefaults { ResumeEntry.write(merged, over: local, to: defaults) }
            resumeSnapshot = merged
            changed.insert("resume")
        }
        onChange?(changed)
    }

    private func applyingDefaults(_ body: () -> Void) {
        applying = true
        body()
        applying = false
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a as NSObject, b as NSObject): a.isEqual(b)
        default: false
        }
    }
}

/// One item of ResumeStore in the synced form: position, duration, when, watched.
struct ResumeEntry: Equatable {
    var position: Double
    var duration: Double
    var at: Date
    var watched: Bool

    static func read(_ defaults: UserDefaults) -> [String: ResumeEntry] {
        var entries: [String: ResumeEntry] = [:]
        for (name, value) in defaults.dictionaryRepresentation() {
            if name.hasPrefix("resume."), name.hasSuffix(".at"), let at = value as? Date {
                let key = String(name.dropFirst("resume.".count).dropLast(".at".count))
                entries[key] = ResumeEntry(position: defaults.double(forKey: "resume." + key),
                                           duration: defaults.double(forKey: "resume." + key + ".duration"),
                                           at: at, watched: defaults.bool(forKey: "watched." + key))
            } else if name.hasPrefix("watched."), value as? Bool == true {
                let key = String(name.dropFirst("watched.".count))
                if entries[key] == nil, defaults.object(forKey: "resume." + key + ".at") == nil {
                    entries[key] = ResumeEntry(position: 0, duration: 0, at: .distantPast, watched: true)
                }
            }
        }
        return entries
    }

    /// Per item the newer position; watched once watched anywhere. A finished item (watched,
    /// no position, no date left) beats a position from a device that has not seen it finish.
    static func merge(_ a: [String: ResumeEntry], _ b: [String: ResumeEntry]) -> [String: ResumeEntry] {
        a.merging(b) { x, y in
            var newer: ResumeEntry
            if x.isFinished && !y.watched { newer = x } else if y.isFinished && !x.watched { newer = y } else { newer = y.at > x.at ? y : x }
            newer.watched = x.watched || y.watched
            return newer
        }
    }

    var isFinished: Bool { watched && position == 0 }

    static func write(_ entries: [String: ResumeEntry], over old: [String: ResumeEntry], to defaults: UserDefaults) {
        for (key, entry) in entries where old[key] != entry {
            if entry.position > 0 {
                defaults.set(entry.position, forKey: "resume." + key)
                if entry.duration > 0 { defaults.set(entry.duration, forKey: "resume." + key + ".duration") }
                defaults.set(entry.at, forKey: "resume." + key + ".at")
            } else {
                for suffix in ["", ".duration", ".at"] { defaults.removeObject(forKey: "resume." + key + suffix) }
            }
            if entry.watched { defaults.set(true, forKey: "watched." + key) }
        }
    }

    static func encode(_ entries: [String: ResumeEntry]) -> [String: Any] {
        entries.mapValues { ["p": $0.position, "d": $0.duration, "t": $0.at, "w": $0.watched] as [String: Any] }
    }

    static func decode(_ object: Any?) -> [String: ResumeEntry] {
        guard let dict = object as? [String: [String: Any]] else { return [:] }
        return dict.compactMapValues { item in
            guard let at = item["t"] as? Date else { return nil }
            return ResumeEntry(position: item["p"] as? Double ?? 0, duration: item["d"] as? Double ?? 0, at: at, watched: item["w"] as? Bool ?? false)
        }
    }
}
