import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import FernsyCore
@testable import FernsyShared

/// An in-memory Fernsy Control: items with change numbers and tombstones, one mailbox.
final class FakeControl: ServerControlAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: ControlClient.Item] = [:]
    private var change = 0
    var mailboxes: [String: (publicKey: Data, tag: Data)] = [:]
    var answers: [String: (message: Data, tag: Data)] = [:]

    func items(_ key: ControlKey, since: Int) async throws -> (items: [ControlClient.Item], change: Int) {
        lock.withLock { (items.values.filter { $0.change > since }.sorted { $0.change < $1.change }, change) }
    }

    func put<Value: Encodable>(_ value: Value, kind: ControlKind, id: String, key: ControlKey) async throws -> Int {
        let data = try key.seal(value, kind: kind, id: id)
        return lock.withLock {
            change += 1
            items["\(kind.rawValue)/\(id)"] = ControlClient.Item(kind: kind.rawValue, id: id, change: change, data: data, deleted: nil)
            return change
        }
    }

    func delete(kind: ControlKind, id: String, key: ControlKey) async throws {
        lock.withLock {
            guard items["\(kind.rawValue)/\(id)"] != nil else { return }
            change += 1
            items["\(kind.rawValue)/\(id)"] = ControlClient.Item(kind: kind.rawValue, id: id, change: change, data: nil, deleted: true)
        }
    }

    func mailbox(_ code: PairingCode) async throws -> (publicKey: Data, tag: Data) {
        guard let box = lock.withLock({ mailboxes[code.mailbox] }) else { throw ControlClient.Failure.notFound }
        return box
    }

    func answer(_ code: PairingCode, message: Data, tag: Data) async throws {
        lock.withLock { answers[code.mailbox] = (message, tag) }
    }
}

@MainActor
struct ServerModelTests {
    let login = XtreamCredentials(server: "https://demo.example", username: "demo", password: "demo")

    func model(_ control: FakeControl) -> (ServerModel, ControlKeyStore) {
        let stored = KeyBox()
        let keys = ControlKeyStore(backing: nil, loadLocal: { stored.key.withLock { $0 } }, saveLocal: { key in stored.key.withLock { $0 = key } })
        let cloud = CloudKeyStore(backing: nil, loadLocal: { nil }, saveLocal: { _ in })
        let model = ServerModel(api: control, keys: keys, cloudKeys: cloud)
        model.pairingPoll = .milliseconds(20)
        return (model, keys)
    }

    final class KeyBox: Sendable { let key = Mutex<ControlKey?>(nil) }

    /// A server waiting with `code`; when the app answers, it opens the secrets and reports.
    func waitingServer(_ control: FakeControl, code: PairingCode) throws -> Task<PairingSecrets?, Never> {
        let server = Curve25519.KeyAgreement.PrivateKey()
        let codeKey = try code.key(rounds: 1000)
        control.mailboxes[code.mailbox] = (server.publicKey.rawRepresentation, PairingCode.tag(server.publicKey.rawRepresentation, key: codeKey))
        return Task.detached {
            for _ in 0..<200 {
                if let answer = control.answers[code.mailbox],
                   let secrets = try? PairingSecrets.open(answer.message, tag: answer.tag, privateKey: server, codeKey: codeKey) {
                    _ = try? await control.put(ControlServerStatus(lastContact: Date(), version: "test"), kind: .server, id: "status", key: secrets.controlKey)
                    return secrets
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return nil
        }
    }

    @Test func pairingHandsTheServerTheKeysAndLogin() async throws {
        let control = FakeControl()
        let (model, keys) = model(control)
        let code = PairingCode()
        let server = try waitingServer(control, code: code)
        try await model.pair(code: code.display.lowercased(), login: login, rounds: 1000)
        let secrets = try #require(await server.value)
        #expect(secrets.login == login)
        #expect(secrets.controlKey == (await keys.key()))
        #expect(model.isPaired)
        #expect(model.isOnline())
    }

    @Test func pairingFailures() async throws {
        let control = FakeControl()
        let (model, _) = model(control)
        await #expect(throws: ServerModel.PairingFailure.badCode) { try await model.pair(code: "12", login: login, rounds: 1000) }
        await #expect(throws: ServerModel.PairingFailure.unknownCode) { try await model.pair(code: PairingCode().value, login: login, rounds: 1000) }
        let code = PairingCode()
        control.mailboxes[code.mailbox] = (Data(repeating: 1, count: 32), Data(repeating: 2, count: 32))
        await #expect(throws: ServerModel.PairingFailure.wrongCode) { try await model.pair(code: code.value, login: login, rounds: 1000) }
    }

    @Test func ordersAndStatesFromBothSides() async throws {
        let control = FakeControl()
        let (model, keys) = model(control)
        let key = try await keys.createIfMissing()
        let order = ControlOrder(channelId: 7, channelName: "Seven", title: "News", showStart: Date(timeIntervalSince1970: 1_800_000_000),
                                 showEnd: Date(timeIntervalSince1970: 1_800_001_800), padBefore: 60, padAfter: 300, createdBy: "iPad")
        let id = try await model.schedule(order)
        #expect(model.pending.map(\.id) == [id])
        _ = try await control.put(ControlOrderState(phase: .recording), kind: .state, id: id, key: key)
        await model.refresh()
        #expect(model.order(channelId: 7, start: order.showStart)?.state?.phase == .recording)
        #expect(model.runningCount == 1)
        #expect(model.runningChannels == [7])
        // Without a report from the server its state does not block anything.
        #expect(model.blockingOrder(for: 3, local: [], limit: 1) == nil)
        _ = try await control.put(ControlServerStatus(lastContact: Date(), version: "test"), kind: .server, id: "status", key: key)
        await model.refresh()
        #expect(model.blockingOrder(for: 3, local: [], limit: 1)?.id == id)
        #expect(model.blockingOrder(for: 3, local: [], limit: 2) == nil)
        #expect(model.blockingOrder(for: 3, local: [5], limit: 2)?.id == id)
        #expect(model.blockingOrder(for: 5, local: [5], limit: 2) == nil)
        try await model.cancel(id)
        await model.refresh()
        #expect(model.orders.isEmpty)
    }

    @Test func removingAndPairingAgain() async throws {
        let control = FakeControl()
        let (model, keys) = model(control)
        let first = PairingCode()
        _ = try waitingServer(control, code: first)
        try await model.pair(code: first.value, login: login, rounds: 1000)
        try await model.remove()
        #expect(!model.isPaired)
        // The server confirms by deleting its status.
        try await control.delete(kind: .server, id: "status", key: try #require(await keys.key()))
        await model.refresh()
        #expect(model.status == nil)
        // Pairing again clears the old removal mark.
        let second = PairingCode()
        _ = try waitingServer(control, code: second)
        try await model.pair(code: second.value, login: login, rounds: 1000)
        #expect(model.isPaired)
        let items = try await control.items(try #require(await keys.key()), since: 0).items
        #expect(items.first { $0.kind == "removed" }?.deleted == true)
    }
}
