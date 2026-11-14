import Foundation

/// At most one run of something per interval (continue-watching-fresh design 1: Jellyfin's rows
/// when the app comes to the front, which on the Mac is every switch between apps).
public struct RefreshThrottle: Sendable {
    public let interval: TimeInterval
    private var last: Date?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// True (and noted) when the last run is at least `interval` ago.
    public mutating func allow(now: Date = Date()) -> Bool {
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}

/// `IPTV_TESTSYNC=memory|memory-keep` (debug builds, continue-watching-fresh design 5): test runs
/// keep positions in memory and do not sync. With the switch, the resume and sync stores use a
/// UserDefaults suite of their own and a stand-in for iCloud, so a UI test can put positions in
/// "from another device" and see them arrive. `memory` empties both at launch, `memory-keep` keeps
/// them for a relaunch. The app's own stored settings are not touched.
public enum TestSync {
    #if DEBUG
    private static let mode = ProcessInfo.processInfo.environment["IPTV_TESTSYNC"]

    /// The suite for ResumeStore and SyncStore; nil without the switch.
    public static let defaults: UserDefaults? = {
        guard mode == "memory" || mode == "memory-keep" else { return nil }
        if mode == "memory" {
            UserDefaults().removePersistentDomain(forName: "fernsy.test.sync")
            UserDefaults().removePersistentDomain(forName: "fernsy.test.sync.cloud")
        }
        return UserDefaults(suiteName: "fernsy.test.sync")
    }()

    /// The stand-in for iCloud's key-value store; nil without the switch.
    public static let backing: SyncBacking? = defaults.flatMap { _ in UserDefaults(suiteName: "fernsy.test.sync.cloud").map(Cloud.init) }

    private final class Cloud: SyncBacking {
        let store: UserDefaults
        init(_ store: UserDefaults) { self.store = store }
        func object(forKey key: String) -> Any? { store.object(forKey: key) }
        func set(_ value: Any?, forKey key: String) { store.set(value, forKey: key) }
        func synchronize() -> Bool { true }
    }

    /// One position as another device would have sent it.
    public struct Remote: Sendable {
        public var key: String
        public var position: Double
        public var duration: Double
        public var series: Int?

        public init(key: String, position: Double, duration: Double, series: Int? = nil) {
            self.key = key
            self.position = position
            self.duration = duration
            self.series = series
        }
    }

    /// Writes positions (and the series of episodes) into the stand-in as another device would,
    /// newer than what this device has; nothing tells the app, as when a notification is missed.
    /// False without the switch.
    @discardableResult
    public static func putFromOtherDevice(_ items: [Remote]) -> Bool {
        guard let backing else { return false }
        var resume = ResumeEntry.decode(backing.object(forKey: "resume"))
        var series = (backing.object(forKey: "resumeSeries") as? [String: Int]) ?? [:]
        for item in items {
            resume[item.key] = ResumeEntry(position: item.position, duration: item.duration, at: Date(), watched: false)
            if let id = item.series, item.key.hasPrefix("episode.") { series[String(item.key.dropFirst("episode.".count))] = id }
        }
        backing.set(ResumeEntry.encode(resume), forKey: "resume")
        backing.set(series, forKey: "resumeSeries")
        AppLog.info(.app, "test: \(items.count) position(s) put in from another device")
        return true
    }

    /// `[{"key":…, "position":…, "duration":…, "series":…}]` as the debug MCP tool passes it.
    public static func remotes(_ list: [[String: Any]]) -> [Remote] {
        list.compactMap { item in
            guard let key = item["key"] as? String, let position = (item["position"] as? NSNumber)?.doubleValue else { return nil }
            return Remote(key: key, position: position, duration: (item["duration"] as? NSNumber)?.doubleValue ?? 0,
                          series: (item["series"] as? NSNumber)?.intValue)
        }
    }
    #else
    public static let defaults: UserDefaults? = nil
    public static let backing: SyncBacking? = nil
    #endif
}
