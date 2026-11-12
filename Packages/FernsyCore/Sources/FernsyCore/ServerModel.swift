#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
import Observation

/// What `ServerModel` needs from Fernsy Control (a protocol so tests can use a fake).
public protocol ServerControlAPI: Sendable {
    func items(_ key: ControlKey, since: Int) async throws -> (items: [ControlClient.Item], change: Int)
    func put<Value: Encodable>(_ value: Value, kind: ControlKind, id: String, key: ControlKey) async throws -> Int
    func delete(kind: ControlKind, id: String, key: ControlKey) async throws
    func mailbox(_ code: PairingCode) async throws -> (publicKey: Data, tag: Data)
    func answer(_ code: PairingCode, message: Data, tag: Data) async throws
}

extension ControlClient: ServerControlAPI {}

/// The apps' side of Fernsy Server (headless-recorder): pairing, the server's status, orders
/// and their states. All of it lives in Fernsy Control, sealed with the control key from iCloud;
/// this model keeps the latest picture and polls while a screen that shows it is open.
@MainActor
@Observable
public final class ServerModel {
    public struct Order: Identifiable, Equatable, Sendable {
        public let id: String
        public var order: ControlOrder
        public var state: ControlOrderState?
    }

    public enum PairingFailure: Error, Equatable {
        /// Not ten characters of the code's alphabet.
        case badCode
        /// No server waits with this code (typo, or the 15 minutes are over).
        case unknownCode
        /// The server's key does not belong to this code.
        case wrongCode
        /// iCloud cannot say whether a control key exists.
        case iCloudLocked
        /// The server did not answer within a minute.
        case noAnswer
        case network(String)
    }

    /// The server's last report; nil when no server is paired.
    public private(set) var status: ControlServerStatus?
    public private(set) var orders: [Order] = []
    /// The server was removed on this device and has not confirmed yet.
    public private(set) var isRemoving = false
    public private(set) var lastError: String?

    @ObservationIgnored private let api: ServerControlAPI
    @ObservationIgnored private let keys: ControlKeyStore
    @ObservationIgnored private let cloudKeys: CloudKeyStore
    @ObservationIgnored private var change = 0
    @ObservationIgnored private var orderValues: [String: ControlOrder] = [:]
    @ObservationIgnored private var stateValues: [String: ControlOrderState] = [:]
    @ObservationIgnored private var removedAt: Date?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var pollers = 0
    /// When Fernsy Control last answered (or iCloud said there is no control key).
    @ObservationIgnored private var refreshedAt: ContinuousClock.Instant?
    @ObservationIgnored public var pollInterval: Duration = .seconds(30)
    @ObservationIgnored public var pairingPoll: Duration = .seconds(3)

    public init(api: ServerControlAPI, keys: ControlKeyStore, cloudKeys: CloudKeyStore) {
        self.api = api
        self.keys = keys
        self.cloudKeys = cloudKeys
    }

    public static func live(cloudKeys: CloudKeyStore) -> ServerModel {
        ServerModel(api: ControlClient.live(), keys: .live(), cloudKeys: cloudKeys)
    }

    public var isPaired: Bool { status != nil && !isRemoving }
    public func isOnline(now: Date = .now) -> Bool { status?.isOnline(now: now) ?? false }

    /// Orders not finished yet: what the server will record or records now.
    public var pending: [Order] { orders.filter { !($0.state?.isFinished ?? false) } }

    /// Recordings the server runs now; they hold connections of the stream limit (spec 4.4).
    public var runningCount: Int { orders.filter { $0.state?.phase == .recording }.count }

    /// The channels the server records now (a channel counts once, as in `RecordingPlan`).
    public var runningChannels: Set<Int> { Set(orders.filter { $0.state?.phase == .recording }.map(\.order.channelId)) }

    /// The server recording that playing `channelId` here would push over the account's limit
    /// (spec "Stream limit across server and apps"): the server's connections count as in use
    /// beside this device's recordings (`local`, their channels). Nil when there is room, or when
    /// the server has not reported for a while (its state may be old).
    public func blockingOrder(for channelId: Int, local: Set<Int>, limit: Int, now: Date = .now) -> Order? {
        guard isPaired, isOnline(now: now) else { return nil }
        let running = orders.filter { $0.state?.phase == .recording }
        guard let first = running.first else { return nil }
        let inUse = Set(running.map(\.order.channelId)).count + local.subtracting([channelId]).count
        return inUse + 1 > limit ? first : nil
    }

    // MARK: Reading

    /// Reads what changed since the last call (everything on the first).
    public func refresh() async {
        guard let key = await keys.key() else {
            status = nil
            orders = []
            refreshedAt = .now
            return
        }
        do {
            let (items, change) = try await api.items(key, since: self.change)
            for item in items { apply(item, key: key) }
            self.change = change
            publish()
            lastError = nil
            refreshedAt = .now
        } catch {
            lastError = "\(error)"
            AppLog.warning(.recordings, "Fernsy Server: no answer from Fernsy Control: \(error)")
        }
    }

    /// One look at launch and when the app comes to the front (design 3, "Polling"), so that
    /// `isPaired` and the server's recordings are known before a screen polls. Nothing when the
    /// last answer is younger than a poll.
    public func refreshIfStale() async {
        if let refreshedAt, ContinuousClock.now - refreshedAt < pollInterval { return }
        let known = status != nil
        await refresh()
        if !known, let status { AppLog.info(.recordings, "Fernsy Server: paired server found (\(status.isOnline() ? "online" : "offline"))") }
    }

    private func apply(_ item: ControlClient.Item, key: ControlKey) {
        let deleted = item.deleted == true
        switch ControlKind(rawValue: item.kind) {
        case .order: orderValues[item.id] = deleted ? nil : try? key.open(item, as: ControlOrder.self)
        case .state: stateValues[item.id] = deleted ? nil : try? key.open(item, as: ControlOrderState.self)
        case .server:
            status = deleted ? nil : try? key.open(item, as: ControlServerStatus.self)
            if deleted { isRemoving = false }
        case .removed: removedAt = deleted ? nil : try? key.open(item, as: Date.self)
        case .login: break
        case nil: break
        }
    }

    private func publish() {
        orders = orderValues.map { Order(id: $0.key, order: $0.value, state: stateValues[$0.key]) }
            .sorted { $0.order.showStart < $1.order.showStart }
    }

    /// Polls while at least one screen asks for it (`stopPolling` when it closes).
    public func startPolling() {
        pollers += 1
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(30))
            }
        }
    }

    public func stopPolling() {
        pollers = max(0, pollers - 1)
        guard pollers == 0 else { return }
        polling?.cancel()
        polling = nil
    }

    // MARK: Pairing

    /// Pairs the server showing `text`: hands it the control key, the cloud key and `login`,
    /// sealed for it, then waits up to a minute for its first report.
    public func pair(code text: String, login: XtreamCredentials, timeout: Duration = .seconds(60),
                     rounds: Int = PairingCode.rounds) async throws(PairingFailure) {
        guard let code = PairingCode(text) else { throw .badCode }
        do {
            // PBKDF2 with 600,000 rounds: off the main actor.
            let codeKey = try await Task.detached { try code.key(rounds: rounds) }.value
            let box: (publicKey: Data, tag: Data)
            do { box = try await api.mailbox(code) } catch ControlClient.Failure.notFound { throw PairingFailure.unknownCode }
            guard PairingCode.isValid(tag: box.tag, for: box.publicKey, key: codeKey) else { throw PairingFailure.wrongCode }
            let controlKey: ControlKey
            do { controlKey = try await keys.createIfMissing() } catch { throw PairingFailure.iCloudLocked }
            // An earlier removal stays in the space; a new pairing must not see it as its own.
            if removedAt != nil { try? await api.delete(kind: .removed, id: "removed", key: controlKey) }
            let started = Date()
            let secrets = PairingSecrets(controlKey: controlKey, cloudKey: await cloudKeys.key(), login: login)
            let sealed = try secrets.seal(to: try Curve25519.KeyAgreement.PublicKey(rawRepresentation: box.publicKey), codeKey: codeKey)
            try await api.answer(code, message: sealed.message, tag: sealed.tag)
            AppLog.info(.recordings, "Fernsy Server: pairing sent, waiting for the server")
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                await refresh()
                if let status, status.lastContact > started.addingTimeInterval(-5) {
                    isRemoving = false
                    AppLog.info(.recordings, "Fernsy Server: paired")
                    return
                }
                try await Task.sleep(for: pairingPoll)
            }
            throw PairingFailure.noAnswer
        } catch let failure as PairingFailure {
            throw failure
        } catch {
            throw .network("\(error)")
        }
    }

    /// Removes the server: it deletes its keys, login and recordings when it next looks (spec).
    public func remove() async throws {
        guard let key = await keys.key() else { return }
        try await api.put(Date(), kind: .removed, id: "removed", key: key)
        isRemoving = true
        AppLog.info(.recordings, "Fernsy Server: removed")
    }

    /// Hands the server this login (server-login-update): it checks it with the provider and
    /// reports the outcome in its status (`loginUpdate`).
    public func useLogin(_ credentials: XtreamCredentials) async throws {
        guard let key = await keys.key() else { throw ControlKeyStore.Locked() }
        let login = ControlLogin(credentials: credentials)
        try await api.put(login, kind: .login, id: "login", key: key)
        sentLoginAt = login.sentAt
        AppLog.info(.recordings, "Fernsy Server: new login sent (\(ControlLogin.display(credentials)))")
    }

    /// When this device last sent a login; until the server answers it shows as waiting.
    public private(set) var sentLoginAt: Date?

    /// The server has not decided on the login this device sent yet.
    public var isCheckingLogin: Bool {
        guard let sent = sentLoginAt else { return false }
        guard let decided = status?.loginUpdate?.sentAt else { return true }
        return decided < sent.addingTimeInterval(-0.001)
    }

    // MARK: Orders

    /// Schedules a show on the server; returns the order's id.
    @discardableResult
    public func schedule(_ order: ControlOrder) async throws -> String {
        guard let key = await keys.key() else { throw ControlKeyStore.Locked() }
        let id = UUID().uuidString
        do {
            try await api.put(order, kind: .order, id: id, key: key)
        } catch {
            AppLog.warning(.recordings, "Fernsy Server: could not schedule \(order.title): \(error)")
            throw error
        }
        orderValues[id] = order
        publish()
        AppLog.info(.recordings, "Fernsy Server: scheduled \(order.title)")
        return id
    }

    /// Cancels an order (or forgets a finished one): the server stops it and drops the file.
    public func cancel(_ id: String) async throws {
        guard let key = await keys.key() else { return }
        try await api.delete(kind: .order, id: id, key: key)
        orderValues[id] = nil
        publish()
    }

    /// The order of this show on this channel, if the server has one.
    public func order(channelId: Int, start: Date) -> Order? {
        orders.first { $0.order.channelId == channelId && abs($0.order.showStart.timeIntervalSince(start)) < 1 }
    }
}
