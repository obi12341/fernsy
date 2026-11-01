import FernsyShared
import Foundation

/// Settings from the environment (server/README.md).
struct Config {
    /// The volume: secrets, state and recordings in progress.
    var data: URL
    /// The status page's port.
    var port: UInt16
    /// Seconds between two polls of Fernsy Control.
    var pollSeconds: Double
    var control: ControlClient
    var version: String

    static let version = "1.0.0"

    static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Config {
        Config(data: URL(fileURLWithPath: env["FERNSY_DATA"] ?? "/data"),
               port: env["FERNSY_PORT"].flatMap(UInt16.init) ?? 8080,
               pollSeconds: env["FERNSY_POLL"].flatMap(Double.init) ?? 30,
               control: ControlClient.live(),
               version: version)
    }
}
