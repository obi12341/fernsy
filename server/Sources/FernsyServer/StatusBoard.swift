import FernsyShared
import Foundation

/// What the status page shows (design 4, 6; spec "Server status"), updated by the server's loop
/// and read by the page's thread.
final class StatusBoard: @unchecked Sendable {
    struct Row: Codable {
        var title: String
        var channel: String
        var start: Date
        var end: Date
        var phase: String
        var reason: String?
    }

    struct Snapshot: Codable {
        var version: String = Config.version
        var paired = false
        /// Shown while unpaired; the page is only reachable in the LAN (docs warn against exposing it).
        var pairingCode: String?
        var pairingExpires: Date?
        var status: ControlServerStatus?
        var orders: [Row] = []
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()

    func update(_ change: (inout Snapshot) -> Void) { lock.withLock { change(&snapshot) } }
    var current: Snapshot { lock.withLock { snapshot } }
}

extension StatusBoard.Snapshot {
    init(version: String) { self.init(); self.version = version }
}
