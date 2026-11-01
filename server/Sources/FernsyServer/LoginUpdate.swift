import FernsyShared
import Foundation

/// A login sent from an app (server-login-update): taken only after the provider accepted it,
/// so a typo never replaces a working login. Pure, for tests.
enum LoginUpdate {
    /// How long the provider may be unreachable before the new login is given up.
    static let patience: TimeInterval = 3600

    /// Whether this login item is new for the server: sent after the pairing and after the last
    /// one it decided on.
    static func isNew(_ login: ControlLogin, pairedAt: Date, lastDecided: Date?) -> Bool {
        login.sentAt > pairedAt && login.sentAt > (lastDecided ?? .distantPast)
    }

    enum Check { case accepted, refused, unreachable }

    /// What to report after a check; nil while it is worth trying again.
    static func outcome(_ check: Check, sentAt: Date, waitingSince: Date, now: Date) -> ControlLoginOutcome? {
        switch check {
        case .accepted: ControlLoginOutcome(sentAt: sentAt, result: .accepted)
        case .refused: ControlLoginOutcome(sentAt: sentAt, result: .refused)
        case .unreachable: now.timeIntervalSince(waitingSince) >= patience ? ControlLoginOutcome(sentAt: sentAt, result: .unreachable) : nil
        }
    }
}
