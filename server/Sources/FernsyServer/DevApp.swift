#if DEBUG
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import FernsyShared
import Foundation

/// Debug builds only: plays the app's part from the command line, so the server can be tested
/// end to end before and beside the apps' UI. The control key lives in `FERNSY_DEV_APP` (a JSON
/// file); the IPTV login comes from `IPTV_SERVER`, `IPTV_USER`, `IPTV_PASS` (the demo server).
///
///   FernsyServer app-pair <code>
///   FernsyServer app-order <channel id> <minutes from now> <minutes long> [title]
///   FernsyServer app-login <user> <password> [server]
///   FernsyServer app-list | app-cancel <order id> | app-remove
enum DevApp {
    static func run(_ arguments: [String]) async throws {
        let env = ProcessInfo.processInfo.environment
        let file = URL(fileURLWithPath: env["FERNSY_DEV_APP"] ?? "dev-app.json")
        let control = ControlClient.live()
        func key() throws -> ControlKey { try JSONDecoder().decode(ControlKey.self, from: Data(contentsOf: file)) }
        switch arguments.first {
        case "app-pair":
            guard arguments.count > 1, let code = PairingCode(arguments[1]) else { throw usage }
            let codeKey = try code.key()
            let box = try await control.mailbox(code)
            guard PairingCode.isValid(tag: box.tag, for: box.publicKey, key: codeKey) else { throw ControlClient.Failure.wrongTag }
            let controlKey = (try? key()) ?? ControlKey()
            try JSONEncoder().encode(controlKey).write(to: file)
            let login = XtreamCredentials(server: env["IPTV_SERVER"] ?? "https://fernsy-demo.mobilistics.workers.dev",
                                          username: env["IPTV_USER"] ?? "demo", password: env["IPTV_PASS"] ?? "demo")
            let sealed = try PairingSecrets(controlKey: controlKey, cloudKey: CloudAccountKey(), login: login)
                .seal(to: try Curve25519.KeyAgreement.PublicKey(rawRepresentation: box.publicKey), codeKey: codeKey)
            try await control.answer(code, message: sealed.message, tag: sealed.tag)
            print("paired; control key in \(file.path)")
        case "app-order":
            guard arguments.count >= 4, let channel = Int(arguments[1]), let from = Double(arguments[2]), let length = Double(arguments[3]) else { throw usage }
            let start = Date().addingTimeInterval(from * 60)
            let order = ControlOrder(channelId: channel, channelName: "Channel \(channel)", title: arguments.count > 4 ? arguments[4] : "Test",
                                     showStart: start, showEnd: start.addingTimeInterval(length * 60), padBefore: 0, padAfter: 0, createdBy: "DevApp")
            let id = UUID().uuidString
            try await control.put(order, kind: .order, id: id, key: try key())
            print(id)
        case "app-list":
            let key = try key()
            for item in try await control.items(key, since: 0).items where item.deleted != true {
                switch ControlKind(rawValue: item.kind) {
                case .order: print("order  \(item.id) \(try key.open(item, as: ControlOrder.self))")
                case .state: print("state  \(item.id) \(try key.open(item, as: ControlOrderState.self))")
                case .server: print("server \(try key.open(item, as: ControlServerStatus.self))")
                default: print("\(item.kind) \(item.id)")
                }
            }
        case "app-cancel":
            guard arguments.count > 1 else { throw usage }
            try await control.delete(kind: .order, id: arguments[1], key: try key())
        case "app-login":
            guard arguments.count >= 3 else { throw usage }
            let login = XtreamCredentials(server: arguments.count > 3 ? arguments[3] : env["IPTV_SERVER"] ?? "https://fernsy-demo.mobilistics.workers.dev",
                                          username: arguments[1], password: arguments[2])
            try await control.put(ControlLogin(credentials: login), kind: .login, id: "login", key: try key())
        case "app-remove":
            try await control.put(Date(), kind: .removed, id: "removed", key: try key())
        default:
            throw usage
        }
    }

    static let usage = CocoaError(.featureUnsupported)
}
#endif
