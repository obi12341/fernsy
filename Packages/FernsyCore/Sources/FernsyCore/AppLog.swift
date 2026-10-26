import Foundation

public enum LogLevel: Int, Comparable, CaseIterable, Sendable {
    /// Frequent or technical data (stats, timing, geometry).
    case detail
    /// Normal milestones (playback started, recording finished, catalog loaded).
    case info
    /// Something the app recovered from or worked around (reconnect, fallback).
    case warning
    /// Something that failed for the user.
    case error

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    public var code: String {
        switch self {
        case .detail: "DETAIL"
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERROR"
        }
    }

    public init?(code: String) {
        guard let level = Self.allCases.first(where: { $0.code == code }) else { return nil }
        self = level
    }
}

public enum LogCategory: String, CaseIterable, Sendable {
    case app, player, network, tuner, timeshift, recordings, catalog, guide, jellyfin, pip, mcp
}

public struct LogEntry: Identifiable, Sendable {
    public let id: Int
    public let date: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String

    public init(id: Int, date: Date, level: LogLevel, category: LogCategory, message: String) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }

    /// One line of the log file and of copied or saved text.
    public var line: String {
        "\(LogEntry.timestamp.string(from: date))\t\(level.code)\t\(category.rawValue)\t\(message)"
    }

    nonisolated(unsafe) static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()
}

/// The app's event log, in every build: the last entries in memory, and a file in the app's
/// Caches folder for this run and the previous one. Callable from any thread; credentials are
/// removed before an entry is stored. Nothing is ever sent anywhere.
public final class AppLog: @unchecked Sendable {
    public static let shared = AppLog()

    public static func detail(_ category: LogCategory, _ message: String) { shared.add(.detail, category, message) }
    public static func info(_ category: LogCategory, _ message: String) { shared.add(.info, category, message) }
    public static func warning(_ category: LogCategory, _ message: String) { shared.add(.warning, category, message) }
    public static func error(_ category: LogCategory, _ message: String) { shared.add(.error, category, message) }

    public static let capacity = 20_000
    public static let maxFileBytes = 4 << 20

    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private var nextID = 0
    private var secrets: [String: String] = [:]

    private let queue = DispatchQueue(label: "fernsy.log", qos: .utility)
    private var pending: [String] = []
    private var flushScheduled = false
    private var file: FileHandle?
    private var fileBytes = 0

    public let folder: URL
    public var currentURL: URL { folder.appendingPathComponent("current.log") }
    public var previousURL: URL { folder.appendingPathComponent("previous.log") }

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = caches.appendingPathComponent("Fernsy/logs", isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // The last run becomes the previous one.
        if fm.fileExists(atPath: currentURL.path) {
            try? fm.removeItem(at: previousURL)
            try? fm.moveItem(at: currentURL, to: previousURL)
        }
        fm.createFile(atPath: currentURL.path, contents: nil)
        file = try? FileHandle(forWritingTo: currentURL)
    }

    // MARK: Writing

    public func add(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        lock.lock()
        let text = redact(message, secrets: Array(secrets.values))
        let entry = LogEntry(id: nextID, date: Date(), level: level, category: category, message: text)
        nextID += 1
        entries.append(entry)
        if entries.count > Self.capacity { entries.removeFirst(Self.capacity / 10) }
        pending.append(Self.escaped(entry.line))
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        #if DEBUG
        debugLog("[\(category.rawValue)] \(text)")
        #endif
        if schedule {
            queue.asyncAfter(deadline: .now() + 0.5) { [self] in flush() }
        }
    }

    private func flush() {
        lock.lock()
        let lines = pending
        pending = []
        flushScheduled = false
        lock.unlock()
        guard let file, !lines.isEmpty else { return }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        file.write(data)
        fileBytes += data.count
        if fileBytes > Self.maxFileBytes { trimFile() }
    }

    /// Keeps the newest half of the file (on the queue).
    private func trimFile() {
        try? file?.close()
        guard let data = try? Data(contentsOf: currentURL) else { return }
        var tail = data.suffix(data.count / 2)
        if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) { tail = tail[(newline + 1)...] }
        try? Data(tail).write(to: currentURL, options: .atomic)
        fileBytes = tail.count
        file = try? FileHandle(forWritingTo: currentURL)
        _ = try? file?.seekToEnd()
    }

    private static func escaped(_ line: String) -> String {
        line.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: Reading

    /// Entries of this run with an id above `id` (all for nil).
    public func entries(after id: Int?) -> [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        guard let id else { return entries }
        guard let last = entries.last, last.id > id else { return [] }
        let start = entries.firstIndex { $0.id > id } ?? entries.count
        return Array(entries[start...])
    }

    /// The previous run, read from its file.
    public func previousRun() -> [LogEntry] {
        guard let text = try? String(contentsOf: previousURL, encoding: .utf8) else { return [] }
        var result: [LogEntry] = []
        for (i, line) in text.split(separator: "\n").enumerated() {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let date = LogEntry.timestamp.date(from: String(parts[0])),
                  let level = LogLevel(code: String(parts[1])), let category = LogCategory(rawValue: String(parts[2])) else { continue }
            result.append(LogEntry(id: i, date: date, level: level, category: category,
                                   message: String(parts[3]).replacingOccurrences(of: "\\n", with: "\n")))
        }
        return result
    }

    /// Empties this run (memory and file).
    public func clear() {
        lock.lock()
        entries = []
        pending = []
        lock.unlock()
        queue.async { [self] in
            try? file?.truncate(atOffset: 0)
            fileBytes = 0
        }
    }

    // MARK: Credentials

    /// Values replaced by "•••" wherever they appear (passwords, tokens); nil removes one.
    public func setSecret(_ key: String, _ value: String?) {
        lock.lock(); defer { lock.unlock() }
        if let value, value.count >= 4 { secrets[key] = value } else { secrets[key] = nil }
    }

    private static let queryCredentials = try! NSRegularExpression(
        pattern: "((?:username|password|api_key|token)=)[^&\\s\"']+", options: [.caseInsensitive])
    private static let pathCredentials = try! NSRegularExpression(
        pattern: "/(live|movie|series|timeshift)/[^/\\s]+/[^/\\s]+/", options: [])

    public func redact(_ message: String, secrets: [String]) -> String {
        var text = message
        let range = { NSRange(text.startIndex..., in: text) }
        text = Self.queryCredentials.stringByReplacingMatches(in: text, range: range(), withTemplate: "$1•••")
        text = Self.pathCredentials.stringByReplacingMatches(in: text, range: range(), withTemplate: "/$1/•••/•••/")
        for secret in secrets {
            text = text.replacingOccurrences(of: secret, with: "•••")
            if let encoded = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), encoded != secret {
                text = text.replacingOccurrences(of: encoded, with: "•••")
            }
        }
        return text
    }
}

extension AppLog {
    /// A filtered slice of the current or previous run, oldest first: at least `minimum`, in
    /// `categories` (all when empty), since `since`, containing `query`; the newest `limit` of
    /// those. Entries are redacted already when they are added.
    public func query(previous: Bool = false, minimum: LogLevel = .info, categories: Set<LogCategory> = [],
               since: Date? = nil, query: String = "", limit: Int = 200) -> (entries: [LogEntry], truncated: Bool) {
        let source = previous ? previousRun() : entries(after: nil)
        let needle = query.lowercased()
        let matching = source.filter { entry in
            entry.level >= minimum
                && (categories.isEmpty || categories.contains(entry.category))
                && (since.map { entry.date >= $0 } ?? true)
                && (needle.isEmpty || entry.message.lowercased().contains(needle))
        }
        return (Array(matching.suffix(limit)), matching.count > limit)
    }
}

#if DEBUG
private let debugStart = Date()

/// Debug builds: a line on stderr with the seconds since launch (test runs read it).
public func debugLog(_ message: String) {
    let t = String(format: "%7.2f", Date().timeIntervalSince(debugStart))
    FileHandle.standardError.write(Data(("\(t) " + message + "\n").utf8))
}
#endif

extension Bundle {
    /// The package's own resources (its string catalog), also for its tests, whose
    /// `Bundle.module` is the test bundle.
    static var fernsyCore: Bundle { .module }
}
