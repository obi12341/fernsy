import Foundation

/// Resume positions and watched marks of IPTV films, episodes and recordings, with the Mac's
/// keys (`resume.<key>`, `resume.<key>.duration`, `watched.<key>`) and rules: under 30 s nothing
/// is kept, within the last 90 s the item counts as watched. `resume.<key>.at` notes when it was
/// last played (Apple TV's Start sorts by it). Without UserDefaults (test runs) it keeps
/// everything in memory.
public final class ResumeStore: @unchecked Sendable {
    private let defaults: UserDefaults?
    private var memory: [String: (position: Double, duration: Double, at: Date)] = [:]
    private var watchedInMemory: Set<String> = []
    private let lock = NSLock()

    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public static func movieKey(_ id: Int) -> String { "movie.\(id)" }
    public static func episodeKey(_ id: Int) -> String { "episode.\(id)" }
    public static func recordingKey(_ id: UUID) -> String { "recording.\(id.uuidString)" }

    public func position(_ key: String) -> Double {
        lock.withLock { defaults.map { $0.double(forKey: "resume." + key) } ?? memory[key]?.position ?? 0 }
    }

    /// 0…1 of a started item, nil without a stored duration.
    public func fraction(_ key: String) -> Double? {
        let position = position(key)
        let duration = lock.withLock { defaults.map { $0.double(forKey: "resume." + key + ".duration") } ?? memory[key]?.duration ?? 0 }
        guard position > 0, duration > 0 else { return nil }
        return min(1, position / duration)
    }

    /// When the item was last stopped with a resume position; nil for items saved before this
    /// was kept, and for finished ones.
    public func lastPlayed(_ key: String) -> Date? {
        lock.withLock {
            if let defaults { return defaults.object(forKey: "resume." + key + ".at") as? Date }
            return memory[key]?.at
        }
    }

    /// Played to its end (within the last 90 s) at some point.
    public func isWatched(_ key: String) -> Bool {
        lock.withLock { defaults.map { $0.bool(forKey: "watched." + key) } ?? watchedInMemory.contains(key) }
    }

    /// Returns true when the item now counts as watched.
    @discardableResult
    public func save(_ key: String, position: Double, duration: Double, at date: Date = Date()) -> Bool {
        let finished = duration > 0 && position > duration - 90
        lock.withLock {
            if let defaults {
                if position < 30 || finished {
                    for suffix in ["", ".duration", ".at"] { defaults.removeObject(forKey: "resume." + key + suffix) }
                } else {
                    defaults.set(position, forKey: "resume." + key)
                    if duration > 0 { defaults.set(duration, forKey: "resume." + key + ".duration") }
                    defaults.set(date, forKey: "resume." + key + ".at")
                }
                if finished { defaults.set(true, forKey: "watched." + key) }
            } else {
                memory[key] = position < 30 || finished ? nil : (position, duration, date)
                if finished { watchedInMemory.insert(key) }
            }
        }
        return finished
    }

    /// The keys with a resume position (prefix such as "movie." or "episode."), newest first.
    public func started(prefix: String) -> [String] {
        lock.withLock {
            let keys: [(String, Date)]
            if let defaults {
                keys = defaults.dictionaryRepresentation().keys.compactMap { name -> (String, Date)? in
                    guard name.hasPrefix("resume." + prefix), !name.hasSuffix(".duration"), !name.hasSuffix(".at") else { return nil }
                    let key = String(name.dropFirst("resume.".count))
                    return (key, defaults.object(forKey: name + ".at") as? Date ?? .distantPast)
                }
            } else {
                keys = memory.filter { $0.key.hasPrefix(prefix) }.map { ($0.key, $0.value.at) }
            }
            return keys.sorted { $0.1 > $1.1 }.map(\.0)
        }
    }

    /// Debug runs: these items count as watched (in memory).
    public func markWatched(_ keys: [String]) {
        lock.withLock { watchedInMemory.formUnion(keys) }
    }
}

/// Rules of the film and series grids shared by the Mac and the Apple TV app.
public enum LibraryRules {
    /// Added within this many days: the Apple TV grid marks it "Neu".
    public static let newDays = 14

    public static func isNew(added: Int, now: Date = Date()) -> Bool {
        added > 0 && now.timeIntervalSince1970 - Double(added) < Double(newDays) * 86_400
    }

    /// The favourites key of a film or series ("movie:<id>", "series:<id>"), as on the Mac.
    public static func favoriteKey(movie id: Int) -> String { "movie:\(id)" }
    public static func favoriteKey(series id: Int) -> String { "series:\(id)" }
}
