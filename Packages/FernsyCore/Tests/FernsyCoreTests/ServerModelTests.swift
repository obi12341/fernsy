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
    /// How often an app asked for items.
    private(set) var reads = 0
    /// Reading fails as without network.
    var offline = false

    func items(_ key: ControlKey, since: Int) async throws -> (items: [ControlClient.Item], change: Int) {
        try lock.withLock {
            if offline { throw URLError(.notConnectedToInternet) }
            reads += 1
            return (items.values.filter { $0.change > since }.sorted { $0.change < $1.change }, change)
        }
    }

    /// The orders in the space that are not deleted.
    func orderCount(_ key: ControlKey) -> Int {
        lock.withLock { items.values.filter { $0.kind == ControlKind.order.rawValue && $0.deleted != true }.count }
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

    /// Launch and coming to the front: one look makes the server known, and a second one right
    /// after it asks nothing.
    @Test func aLookAtLaunchMakesTheServerKnown() async throws {
        let control = FakeControl()
        let (model, keys) = model(control)
        let key = try await keys.createIfMissing()
        _ = try await control.put(ControlServerStatus(lastContact: Date(), version: "test"), kind: .server, id: "status", key: key)
        #expect(!model.isPaired)
        await model.refreshIfStale()
        #expect(model.isPaired)
        #expect(control.reads == 1)
        await model.refreshIfStale()
        #expect(control.reads == 1)
        // Older than a poll: it asks again.
        model.pollInterval = .zero
        await model.refreshIfStale()
        #expect(control.reads == 2)
    }

    /// A paired server and an order for a show that starts `startsIn` seconds from `now`.
    func paired(_ control: FakeControl) async throws -> (ServerModel, ControlKey) {
        let (model, keys) = model(control)
        let key = try await keys.createIfMissing()
        _ = try await control.put(ControlServerStatus(lastContact: Date(), version: "test"), kind: .server, id: "status", key: key)
        return (model, key)
    }

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func show(startsIn: TimeInterval, channel: Int = 7, by device: String = "Mac") -> ControlOrder {
        ControlOrder(channelId: channel, channelName: "Seven", title: "News", showStart: now + startsIn, showEnd: now + startsIn + 1800,
                     padBefore: 600, padAfter: 600, createdBy: device)
    }

    /// Ordering looks at the server's orders first: a show another device ordered is not
    /// ordered again, a failed order does not stand in the way.
    @Test func orderingAShowTwiceKeepsOneOrder() async throws {
        let control = FakeControl()
        let (model, key) = try await paired(control)
        _ = try await control.put(show(startsIn: 7200, by: "Apple TV"), kind: .order, id: "tv", key: key)
        let again = try await model.place(show(startsIn: 7200), streamsInUse: 0, limit: 1, now: now)
        #expect(again.isNew == false)
        #expect(again.order.id == "tv")
        #expect(control.orderCount(key) == 1)
        // Another show is new, and listed without a second look.
        let other = try await model.place(show(startsIn: 10800), streamsInUse: 0, limit: 1, now: now)
        #expect(other.isNew)
        #expect(model.pendingOrder(channelId: 7, start: now + 10800)?.id == other.order.id)
        #expect(control.orderCount(key) == 2)
        // Guides mark both shows.
        #expect(model.markingOrder(channelId: 7, start: now + 7200)?.id == "tv")
        #expect(model.markingOrder(channelId: 7, start: now + 10800) != nil)
        #expect(model.markingOrder(channelId: 8, start: now + 7200) == nil)
        // The server gave up on the first: it can be ordered anew, and marks nothing until then.
        _ = try await control.put(ControlOrderState(phase: .failed, reason: .noStream), kind: .state, id: "tv", key: key)
        await model.refresh()
        #expect(model.markingOrder(channelId: 7, start: now + 7200) == nil)
        let anew = try await model.place(show(startsIn: 7200), streamsInUse: 0, limit: 1, now: now)
        #expect(anew.isNew)
        #expect(control.orderCount(key) == 3)
    }

    /// Two clicks on the same show at once (seen with Fernsy Dev's debug order, which ran twice):
    /// the second waits for the first and finds its order.
    @Test func orderingTheSameShowAtOnceKeepsOneOrder() async throws {
        let control = FakeControl()
        let (model, key) = try await paired(control)
        async let first = model.place(show(startsIn: 7200), streamsInUse: 0, limit: 1, now: now)
        async let second = model.place(show(startsIn: 7200), streamsInUse: 0, limit: 1, now: now)
        async let third = model.place(show(startsIn: 7200), streamsInUse: 0, limit: 1, now: now)
        let results = try await [first, second, third]
        #expect(results.filter(\.isNew).count == 1)
        #expect(Set(results.map(\.order.id)).count == 1)
        #expect(control.orderCount(key) == 1)
    }

    /// An order that would start now needs a free stream; one for later is not checked.
    @Test func orderThatStartsNowNeedsAFreeStream() async throws {
        let control = FakeControl()
        let (model, key) = try await paired(control)
        // The show runs, and this device plays on a single-stream account.
        await #expect(throws: ServerModel.OrderFailure.streamsInUse(limit: 1)) {
            try await model.place(show(startsIn: -300), streamsInUse: 1, limit: 1, now: now)
        }
        // Inside the lead time counts as now.
        await #expect(throws: ServerModel.OrderFailure.streamsInUse(limit: 1)) {
            try await model.place(show(startsIn: 300), streamsInUse: 1, limit: 1, now: now)
        }
        #expect(control.orderCount(key) == 0)
        // Later shows are the server's business at their start.
        #expect(try await model.place(show(startsIn: 7200), streamsInUse: 1, limit: 1, now: now).isNew)
        // Room for the server: two streams, one in use here.
        #expect(try await model.place(show(startsIn: -300), streamsInUse: 1, limit: 2, now: now).isNew)
        // The server's own running recording takes that room.
        let running = try #require(model.pendingOrder(channelId: 7, start: now - 300))
        _ = try await control.put(ControlOrderState(phase: .recording), kind: .state, id: running.id, key: key)
        await #expect(throws: ServerModel.OrderFailure.streamsInUse(limit: 2)) {
            try await model.place(show(startsIn: -200, channel: 9), streamsInUse: 1, limit: 2, now: now)
        }
        #expect(control.orderCount(key) == 2)
    }

    @Test func orderingWithoutAServerOrWithoutAnAnswer() async throws {
        let control = FakeControl()
        let (unpaired, _) = model(control)
        await #expect(throws: ServerModel.OrderFailure.notPaired) {
            try await unpaired.place(show(startsIn: 7200), streamsInUse: 0, limit: 1, now: now)
        }
        let (model, key) = try await paired(control)
        await model.refresh()
        control.offline = true
        do {
            _ = try await model.place(show(startsIn: 7200), streamsInUse: 0, limit: 1, now: now)
            Issue.record("ordered without an answer from Fernsy Control")
        } catch {
            guard case .network = error else { Issue.record("\(error)"); return }
        }
        #expect(control.orderCount(key) == 0)
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

    @Test func sendingALoginWaitsForTheServersAnswer() async throws {
        let control = FakeControl()
        let (model, keys) = model(control)
        let key = try await keys.createIfMissing()
        let login = XtreamCredentials(server: "https://tv.example", username: "anna", password: "new")
        try await model.useLogin(login)
        #expect(model.isCheckingLogin)
        let sent = try #require(model.sentLoginAt)
        let item = try #require(try await control.items(key, since: 0).items.first { $0.kind == "login" })
        #expect(try key.open(item, as: ControlLogin.self).credentials == login)
        // The server answers in its status.
        _ = try await control.put(ControlServerStatus(lastContact: Date(), version: "test", login: "anna @ tv.example",
                                                      loginUpdate: ControlLoginOutcome(sentAt: sent, result: .refused)),
                                  kind: .server, id: "status", key: key)
        await model.refresh()
        #expect(!model.isCheckingLogin)
        #expect(model.status?.loginUpdate?.result == .refused)
    }
}
