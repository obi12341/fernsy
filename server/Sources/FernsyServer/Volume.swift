#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import FernsyShared
import Foundation

/// The data volume (design 6, spec "Docker image"): `secrets.json` (mode 600, from pairing),
/// `state.json` (orders, states, uploads) and `recordings/<order id>.ts`.
struct Volume {
    let root: URL

    var secretsURL: URL { root.appendingPathComponent("secrets.json") }
    var stateURL: URL { root.appendingPathComponent("state.json") }
    var recordings: URL { root.appendingPathComponent("recordings") }

    func recordingURL(_ id: String) -> URL { recordings.appendingPathComponent("\(id).ts") }

    func fileSize(_ id: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: recordingURL(id).path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
    }

    // MARK: Secrets

    func loadSecrets() -> PairingSecrets? {
        guard let data = try? Data(contentsOf: secretsURL) else { return nil }
        return try? JSONDecoder().decode(PairingSecrets.self, from: data)
    }

    func saveSecrets(_ secrets: PairingSecrets) throws {
        let data = try JSONEncoder().encode(secrets)
        let temp = root.appendingPathComponent(".secrets.json.tmp")
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]),
              rename(temp.path, secretsURL.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: secretsURL.path])
        }
    }

    /// Removing the server in an app (spec "Pairing with an app": "deletes its keys and login"):
    /// secrets, state and every recording that was not uploaded.
    func wipe() {
        try? FileManager.default.removeItem(at: secretsURL)
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: recordings)
        try? prepare()
    }

    // MARK: State

    func loadState() -> ServerState {
        guard let data = try? Data(contentsOf: stateURL) else { return ServerState() }
        return (try? JSONDecoder().decode(ServerState.self, from: data)) ?? ServerState()
    }

    func saveState(_ state: ServerState) {
        do {
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        } catch {
            Log.error("Could not save the state: \(error.localizedDescription)")
        }
    }

    var freeBytes: Int64? {
        (try? FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber)?.int64Value
    }
}

/// What survives a restart (spec "Restart": "comes back paired and keeps the orders").
struct ServerState: Codable {
    /// Fernsy Control change number read so far.
    var change = 0
    /// When this pairing happened: an older `removed` mark in the space belongs to an earlier one.
    var pairedAt = Date()
    var orders: [String: ControlOrder] = [:]
    var states: [String: ControlOrderState] = [:]
    /// Recordings in progress or waiting for upload, by order id.
    var recordings: [String: LocalRecording] = [:]
    var uploads: [String: CloudUploadJob] = [:]
    /// A login from an app waiting for its check, since when, and the last decision
    /// (server-login-update).
    var pendingLogin: ControlLogin?
    var pendingLoginSince: Date?
    var loginOutcome: ControlLoginOutcome?
}

struct LocalRecording: Codable {
    var start: Date
    var end: Date?
    var gaps: [RecordingGap] = []
    var bytes: Int64 = 0
    /// Set when the upload failed for good (quota, subscription): the file goes after 7 days.
    var keepUntil: Date?
}
