import Foundation

/// What the apps say about Fernsy Server and its orders (headless-recorder), the same on every
/// device.
public enum ServerText {
    public static func phase(_ state: ControlOrderState?) -> String {
        switch state?.phase {
        case nil: String(localized: "Sent to the server", bundle: .module)
        case .scheduled: String(localized: "Scheduled on the server", bundle: .module)
        case .recording: String(localized: "Recording on the server", bundle: .module)
        case .uploading: String(localized: "Uploading to Fernsy Cloud", bundle: .module)
        case .done: String(localized: "Recorded, in Fernsy Cloud", bundle: .module)
        case .failed: String(localized: "Failed", bundle: .module)
        case .refused: String(localized: "Not possible", bundle: .module)
        }
    }

    /// The state with its reason, for a row: "Failed – the show was over …".
    public static func describe(_ state: ControlOrderState?) -> String {
        guard let reason = state?.reason else { return phase(state) }
        return phase(state) + " – " + Self.reason(reason)
    }

    public static func reason(_ reason: ControlOrderState.Reason) -> String {
        switch reason {
        case .streamLimit: String(localized: "the server’s other recordings use all streams of the account", bundle: .module)
        case .missed: String(localized: "the show was over before the server could start", bundle: .module)
        case .noSubscription: String(localized: "Fernsy Cloud has no active subscription", bundle: .module)
        case .quota: String(localized: "Fernsy Cloud storage is full; the server keeps the file for 7 days", bundle: .module)
        case .noStream: String(localized: "the provider delivered nothing", bundle: .module)
        case .login: String(localized: "the provider refused the login", bundle: .module)
        case .disk: String(localized: "the server’s disk is full", bundle: .module)
        case .upload: String(localized: "the upload failed", bundle: .module)
        }
    }

    /// "Online" or "Offline since …" (spec "Server offline": after 10 minutes without a report).
    public static func connection(_ status: ControlServerStatus, now: Date = .now) -> String {
        if status.isOnline(now: now) { return String(localized: "Online", bundle: .module) }
        let time = status.lastContact.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Offline since \(time)", bundle: .module)
    }

    public static func pairing(_ failure: ServerModel.PairingFailure) -> String {
        switch failure {
        case .badCode: String(localized: "The code has ten letters and digits, like 7K3Q-ABCDEF.", bundle: .module)
        case .unknownCode: String(localized: "No server shows this code. Check it, or wait for the server’s next code.", bundle: .module)
        case .wrongCode: String(localized: "This code does not match the server. Check it and try again.", bundle: .module)
        case .iCloudLocked: String(localized: "iCloud is not available, so Fernsy cannot share the server with your other devices. Try again later.", bundle: .module)
        case .noAnswer: String(localized: "The server did not answer. Check that it is running and connected to the internet.", bundle: .module)
        case .network: String(localized: "Fernsy cannot reach the internet right now.", bundle: .module)
        }
    }
}
