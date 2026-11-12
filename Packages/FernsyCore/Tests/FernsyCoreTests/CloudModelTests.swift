import Foundation
import Testing
@testable import FernsyCore
@testable import FernsyShared

/// The purchase path (cloud-account-from-icloud-key 2.4) with a fake App Store and a stubbed
/// server: opening creates no key, a purchase registers the key first and carries its account
/// id as `appAccountToken`, restore links on a second device, a foreign subscription can be
/// moved, expiry and refund end it, and deleting cloud data empties the list. StoreKit itself
/// needs an app host; the real purchase is checked on devices (task 5.4).
@MainActor
@Suite(.serialized)
struct CloudModelTests {
    final class FakeStore: CloudStore, @unchecked Sendable {
        let lock = NSLock()
        var entitled = false
        var tokens: [UUID] = []
        var syncs = 0
        var finished = 0
        /// false: StoreKit answers with an old, expired transaction instead of a new purchase.
        var purchaseEntitles = true
        func offer() async -> CloudModel.Offer? { .init(name: "Fernsy Cloud", price: "2,99 €") }
        func hasEntitlement() async -> Bool { lock.withLock { entitled } }
        func purchase(token: UUID) async throws -> Bool {
            lock.withLock { tokens.append(token); if purchaseEntitles { entitled = true } }
            return true
        }
        func sync() async throws { lock.withLock { syncs += 1 } }
        func finishUnfinished() async { lock.withLock { finished += 1 } }
        func originalTransactionId() async -> String? { lock.withLock { entitled || !tokens.isEmpty ? "2000000000000001" : nil } }
        func set(entitled value: Bool) { lock.withLock { entitled = value } }
    }

    /// The server: `/v1/subscription` answers 409 while `foreign` is set, unless `move` is sent.
    final class Server: URLProtocol {
        nonisolated(unsafe) static var calls: [(method: String, path: String, auth: String, body: [String: Any])] = []
        nonisolated(unsafe) static var state = "none"
        nonisolated(unsafe) static var foreign = false
        /// Every request fails as without network.
        nonisolated(unsafe) static var offline = false
        nonisolated(unsafe) static var recordings = #"[{"id":"r1","dataBytes":10,"metaBytes":5,"completedAt":"2026-10-30T10:00:00Z"}]"#
        nonisolated(unsafe) static var web = false
        static func reset() { calls = []; state = "none"; foreign = false; offline = false; web = false }
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let path = request.url?.path ?? ""
            if Self.offline {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let body = (try? JSONSerialization.jsonObject(with: CloudClientTests.body(of: request))) as? [String: Any] ?? [:]
            Self.calls.append((request.httpMethod ?? "", path, request.value(forHTTPHeaderField: "Authorization") ?? "", body))
            var status = 200
            var text = #"{"state":"\#(Self.state)","usedBytes":0,"totalBytes":1000}"#
            switch (request.httpMethod, path) {
            case ("POST", "/v1/subscription"):
                if Self.foreign && body["move"] as? Bool != true {
                    status = 409; text = #"{"error":"other_account"}"#
                } else {
                    Self.foreign = false; Self.state = "active"
                    text = #"{"state":"active","usedBytes":0,"totalBytes":1000}"#
                }
            case ("DELETE", "/v1/account"): Self.recordings = "[]"; text = "{}"
            case ("GET", "/v1/account") where Self.state == "active" && Self.web:
                text = #"{"state":"active","usedBytes":0,"totalBytes":1000,"provider":"stripe"}"#
            case ("GET", "/v1/offer"): text = #"{"price":{"amount":"€2.99","currency":"EUR"}}"#
            case ("POST", "/v1/checkout"):
                if Self.state == "active" { status = 409; text = #"{"error":"already_subscribed"}"# } else { text = #"{"token":"tok.sig","price":null}"# }
            case ("POST", "/v1/subscription/portal"): text = #"{"url":"https://billing.stripe.com/p/session/test_1"}"#
            case ("GET", "/v1/recordings"): text = #"{"recordings":\#(Self.recordings)}"#
            default: break
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    final class Memory: @unchecked Sendable { var key: CloudAccountKey? }

    func model(_ store: FakeStore, _ memory: Memory) -> CloudModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Server.self]
        let client = CloudClient(baseURL: URL(string: "https://cloud.test")!, urlSession: URLSession(configuration: config), credential: .none)
        let keys = CloudKeyStore(backing: nil, loadLocal: { memory.key }, saveLocal: { memory.key = $0 }, macOverride: .known)
        return CloudModel(client: client, keys: keys, store: store, server: Self.server(FakeControl(), key: nil, keys))
    }

    /// Fernsy Server's model on a fake control service, without iCloud; `key` is the control key
    /// of a user who paired a server.
    static func server(_ control: FakeControl, key: ControlKey?, _ keys: CloudKeyStore) -> ServerModel {
        ServerModel(api: control, keys: ControlKeyStore(backing: nil, loadLocal: { key }, saveLocal: { _ in }), cloudKeys: keys)
    }

    /// Launch reads the paired server's state, so "Record on Server" shows before Recordings or
    /// the server's settings were opened; without a cloud account it asks nothing.
    @Test func launchReadsTheServersState() async throws {
        Server.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Server.self]
        let control = FakeControl(), controlKey = ControlKey()
        _ = try await control.put(ControlServerStatus(lastContact: Date(), version: "test"), kind: .server, id: "status", key: controlKey)
        func cloud(_ memory: Memory) -> CloudModel {
            let client = CloudClient(baseURL: URL(string: "https://cloud.test")!, urlSession: URLSession(configuration: config), credential: .none)
            let keys = CloudKeyStore(backing: nil, loadLocal: { memory.key }, saveLocal: { memory.key = $0 }, macOverride: .known)
            return CloudModel(client: client, keys: keys, store: FakeStore(), server: Self.server(control, key: controlKey, keys))
        }
        let without = cloud(Memory())
        await without.start()
        #expect(!without.server.isPaired)
        #expect(control.reads == 0)
        let memory = Memory()
        memory.key = CloudAccountKey()
        let with = cloud(memory)
        await with.start()
        #expect(with.server.isPaired)
        #expect(control.reads == 1)
        // Coming to the front right after launch asks nothing again.
        await with.refreshServer()
        #expect(control.reads == 1)
    }

    @Test func purchaseRegistersFirstAndCarriesTheToken() async throws {
        Server.reset()
        let store = FakeStore(), memory = Memory()
        let cloud = model(store, memory)
        await cloud.start()
        #expect(!cloud.hasSubscription && !cloud.hasAccount)
        #expect(memory.key == nil, "opening must not create a key")
        #expect(Server.calls.isEmpty)
        #expect(cloud.offer?.price == "2,99 €")
        #expect(store.finished == 1, "leftover renewals are finished at launch")

        #expect(await cloud.purchase())
        let key = try #require(memory.key)
        #expect(store.tokens == [UUID(uuidString: key.accountId)!])
        // Registered (GET /v1/account) with the key before the purchase, then linked.
        #expect(Server.calls.first?.path == "/v1/account")
        #expect(Server.calls.first?.auth.hasPrefix("Key \(key.accountId):") == true)
        #expect(Server.calls.contains { $0.path == "/v1/subscription" && $0.body["originalTransactionId"] as? String == "2000000000000001" })
        #expect(cloud.account?.state == .active)
        #expect(cloud.items.map(\.id) == ["r1"])
    }

    /// A purchase that leaves no active subscription says so instead of doing nothing.
    @Test func purchaseWithoutSubscriptionSaysSo() async throws {
        Server.reset()
        let store = FakeStore(), memory = Memory()
        store.purchaseEntitles = false
        let cloud = model(store, memory)
        await cloud.start()
        #expect(await cloud.purchase() == false)
        guard case .failed(let message) = cloud.phase else { Issue.record("no message: \(cloud.phase)"); return }
        #expect(message.contains("did not confirm"))
        #expect(!Server.calls.contains { $0.path == "/v1/subscription" })
    }

    @Test func secondDeviceRestoresWithTheSameKey() async throws {
        Server.reset()
        let store = FakeStore(), memory = Memory()
        memory.key = CloudAccountKey()
        store.set(entitled: true)
        let ipad = model(store, memory)
        await ipad.start()
        // Launch links an entitlement whose account is not active yet, without any prompt.
        #expect(ipad.hasSubscription)
        #expect(Server.calls.contains { $0.path == "/v1/subscription" })
        #expect(await ipad.restore())
        #expect(store.syncs == 1)
        #expect(Server.calls.allSatisfy { $0.auth.hasPrefix("Key \(memory.key!.accountId):") })
    }

    @Test func foreignSubscriptionCanBeMoved() async throws {
        Server.reset()
        Server.foreign = true
        let store = FakeStore(), memory = Memory()
        memory.key = CloudAccountKey()
        store.set(entitled: true)
        let cloud = model(store, memory)
        await cloud.start()
        #expect(cloud.canMoveSubscription)
        #expect(cloud.account?.state != .active)
        await cloud.moveSubscription()
        #expect(!cloud.canMoveSubscription)
        #expect(cloud.account?.state == .active)
        #expect(Server.calls.last { $0.path == "/v1/subscription" }?.body["move"] as? Bool == true)
    }

    @Test func expiryAndRefundEndIt() async throws {
        Server.reset()
        let store = FakeStore(), memory = Memory()
        let cloud = model(store, memory)
        #expect(await cloud.purchase())
        store.set(entitled: false)  // StoreKit drops expired and refunded entitlements alike.
        await cloud.refreshSubscription()
        #expect(!cloud.hasSubscription)
    }

    @Test func deletingCloudDataEmptiesTheList() async throws {
        Server.reset()
        Server.recordings = #"[{"id":"r1","dataBytes":10,"metaBytes":5,"completedAt":"2026-10-30T10:00:00Z"}]"#
        let store = FakeStore(), memory = Memory()
        let cloud = model(store, memory)
        #expect(await cloud.purchase())
        #expect(!cloud.items.isEmpty)
        try await cloud.deleteCloudData()
        #expect(cloud.items.isEmpty)
        #expect(Server.calls.contains { $0.method == "DELETE" && $0.path == "/v1/account" })
        #expect(memory.key != nil, "the key stays")
    }

    // MARK: Downloads (offline-recording-downloads 1.3)

    /// A model with a key and two finished downloads, r1 and r2.
    func modelWithDownloads() async throws -> (CloudModel, CloudDownloads, URL) {
        let memory = Memory()
        memory.key = CloudAccountKey()
        let cloud = model(FakeStore(), memory)
        let dir = CloudDownloadsTests.directory()
        let transfer = CloudDownloadsTests.FakeTransfer()
        let fixtures = try ["r1", "r2"].map { try CloudDownloadsTests.Fixture(id: $0, bytes: 100) }
        let downloads = CloudDownloadsTests.store(dir, transfer, fixtures)
        for fixture in fixtures {
            try downloads.add(fixture.item)
            await CloudDownloadsTests.waitUntil { transfer.started.contains { $0.id == fixture.id } }
            transfer.onEvent?(.finished(id: fixture.id, file: try CloudDownloadsTests.staged(fixture.data)))
        }
        #expect(downloads.downloads.filter { $0.state == .downloaded }.count == 2)
        cloud.downloads = downloads
        await cloud.connect()
        return (cloud, downloads, dir)
    }

    @Test func downloadFollowsADeletionElsewhere() async throws {
        Server.reset()
        Server.state = "active"
        Server.recordings = #"[{"id":"r1","dataBytes":10,"metaBytes":5,"completedAt":"2026-10-30T10:00:00Z"}]"#
        let (cloud, downloads, dir) = try await modelWithDownloads()
        defer { try? FileManager.default.removeItem(at: dir) }
        await cloud.refresh()
        #expect(downloads.downloads.map(\.id) == ["r1"])
    }

    @Test func downloadsStayAfterTheSubscriptionEnded() async throws {
        Server.reset()
        Server.state = "ended"
        Server.recordings = "[]"
        let (cloud, downloads, dir) = try await modelWithDownloads()
        defer { try? FileManager.default.removeItem(at: dir) }
        await cloud.refresh()
        #expect(downloads.downloads.count == 2)
    }

    @Test func downloadsStayWhenTheListFails() async throws {
        Server.reset()
        Server.state = "active"
        let (cloud, downloads, dir) = try await modelWithDownloads()
        defer { try? FileManager.default.removeItem(at: dir) }
        Server.offline = true
        await cloud.refresh()
        #expect(downloads.downloads.count == 2)
        guard case .failed = cloud.phase else { Issue.record("no failure shown"); return }
    }

    @Test func deletingCloudDataRemovesDownloads() async throws {
        Server.reset()
        Server.state = "active"
        Server.recordings = #"[{"id":"r1","dataBytes":10,"metaBytes":5,"completedAt":"2026-10-30T10:00:00Z"},{"id":"r2","dataBytes":10,"metaBytes":5,"completedAt":"2026-10-30T10:00:00Z"}]"#
        let (cloud, downloads, dir) = try await modelWithDownloads()
        defer { try? FileManager.default.removeItem(at: dir) }
        await cloud.refresh()
        #expect(downloads.downloads.count == 2)
        try await cloud.delete(try #require(cloud.items.first { $0.id == "r2" }))
        #expect(downloads.downloads.map(\.id) == ["r1"])
        try await cloud.deleteCloudData()
        #expect(downloads.downloads.isEmpty)
    }

    // MARK: DMG (stripe-cloud-subscription)

    final class Opened: @unchecked Sendable { var urls: [URL] = [] }

    func webModel(_ memory: Memory, _ opened: Opened) -> CloudModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Server.self]
        let client = CloudClient(baseURL: URL(string: "https://cloud.test")!, urlSession: URLSession(configuration: config), credential: .none)
        let keys = CloudKeyStore(backing: nil, loadLocal: { memory.key }, saveLocal: { memory.key = $0 }, macOverride: .known)
        let model = CloudModel(client: client, keys: keys, store: WebCloudStore(client: client, checkoutPage: { URL(string: "https://www.fernsy.app/cloud.html")! },
                                                                                  open: { opened.urls.append($0) }),
                               server: Self.server(FakeControl(), key: nil, keys))
        model.checkoutPoll = (.milliseconds(50), .seconds(5))
        return model
    }

    @Test func dmgOffersTheWebsitePriceAndOpensTheCheckout() async throws {
        Server.reset()
        Server.web = true
        let memory = Memory(), opened = Opened()
        let cloud = webModel(memory, opened)
        await cloud.start()
        #expect(cloud.offer?.price == "€2.99")
        #expect(memory.key == nil, "the offer needs no key")

        #expect(await cloud.purchase() == false)
        let url = try #require(opened.urls.first)
        #expect(url.absoluteString.hasPrefix("https://www.fernsy.app/") && url.query == "t=tok.sig")
        #expect(cloud.isAwaitingCheckout)
        // Stripe's webhook arrives: the next poll sees the account active.
        Server.state = "active"
        for _ in 0..<100 where cloud.isAwaitingCheckout { try await Task.sleep(for: .milliseconds(20)) }
        #expect(cloud.hasSubscription)
        #expect(!cloud.isAwaitingCheckout)
        #expect(cloud.account?.isWebPurchase == true)
        #expect(await cloud.manageSubscriptionURL()?.host == "billing.stripe.com")
        // Already subscribed: no second checkout.
        #expect(await cloud.purchase())
        #expect(opened.urls.count == 1)
    }

}
