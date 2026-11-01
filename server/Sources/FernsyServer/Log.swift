import Foundation

/// One line per event on stdout (Docker's log). Never credentials, keys, stream URLs or the
/// pairing code's secret part (spec "Server status"); channels and titles are fine, it is the
/// user's own log.
enum Log {
    static func info(_ message: String) { write("INFO", message) }
    static func warning(_ message: String) { write("WARN", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static let lock = NSLock()

    private static func write(_ level: String, _ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(level) \(message)\n"
        lock.withLock { FileHandle.standardOutput.write(Data(line.utf8)) }
    }
}
