import FernsyShared
import Foundation

/// When the server sends its status to Fernsy Control (control-fewer-writes): when anything the
/// apps show changed, and otherwise every 5 minutes as a sign of life with the last contact and
/// free space. The apps call a server offline after 10 minutes without a report.
enum StatusReport {
    static let heartbeat: TimeInterval = 300

    static func isDue(_ status: ControlServerStatus, lastSent: ControlServerStatus?, lastSentAt: Date, now: Date) -> Bool {
        guard let lastSent else { return true }
        if now.timeIntervalSince(lastSentAt) >= heartbeat { return true }
        return comparable(status) != comparable(lastSent)
    }

    /// The status without what changes on every poll.
    private static func comparable(_ status: ControlServerStatus) -> ControlServerStatus {
        var status = status
        status.lastContact = .distantPast
        status.freeBytes = nil
        return status
    }
}
