import FernsyCore
import Foundation

public enum PlayerError: LocalizedError {
    case message(String)
    case offline
    /// The tuner cannot remux these streams (timeshift unavailable).
    case unsupported
    /// Debug builds stream only from the demo server or a local test server, so a test never
    /// takes the stream slot of the developer's own account (`IPTV_ALLOWREAL=1` lifts it).
    case debugRealProvider

    public var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .offline: return String(localized: "This channel is currently offline at your provider.", bundle: .module)
        case .unsupported: return String(localized: "Timeshift is not available for this channel.", bundle: .module)
        case .debugRealProvider: return String(localized: "Debug build: real providers only with IPTV_ALLOWREAL=1", bundle: .module)
        }
    }

    #if DEBUG
    /// Xtream stream URLs (live, films, episodes, catch-up) of other servers are refused;
    /// Jellyfin and local files are not Xtream streams and pass.
    public static func debugAllows(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.scheme?.hasPrefix("http") == true else { return true }
        let xtream = ["live", "movie", "series", "timeshift"].contains(url.pathComponents.dropFirst().first ?? "")
        guard xtream else { return true }
        if ["fernsy-demo.mobilistics.workers.dev", "127.0.0.1", "localhost"].contains(host) { return true }
        if ProcessInfo.processInfo.environment["IPTV_ALLOWREAL"] == "1" { return true }
        AppLog.error(.player, "debug build refused a stream from \(host) (IPTV_ALLOWREAL=1 allows it)")
        return false
    }
    #endif
}
