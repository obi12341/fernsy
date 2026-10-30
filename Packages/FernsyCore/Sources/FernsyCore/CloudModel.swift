import Foundation
import Observation
import StoreKit

/// Whether Fernsy Cloud shows at all (add-recording-cloud design H): the build setting
/// `FERNSY_CLOUD = YES` (Info.plist key `FernsyCloud`), or in debug builds `IPTV_CLOUD`.
public enum CloudFeature {
    public static var isEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_CLOUD"] != nil { return true }
        #endif
        let value = Bundle.main.object(forInfoDictionaryKey: "FernsyCloud")
        return (value as? String)?.uppercased() == "YES" || (value as? Bool) == true
    }

    /// The auto-renewable subscription (App Store Connect product id).
    public static let productID = "de.mobilistics.fernsy.cloud.monthly"
}

/// The App Store side of Fernsy Cloud (a protocol, because StoreKit needs an app host and
/// `swift test` has none; `CloudModelTests` use a fake).
public protocol CloudStore: Sendable {
    /// "Fernsy Cloud · 2,99 €", or nil while the App Store cannot say.
    func offer() async -> CloudModel.Offer?
    func hasEntitlement() async -> Bool
    /// Buys the subscription for the account `token`; false when cancelled or pending.
    func purchase(token: UUID) async throws -> Bool
    func sync() async throws
    /// Finishes transactions the app has not finished yet (renewals that arrived while it ran).
    /// StoreKit hands an unfinished one back from `purchase` instead of showing the sheet.
    func finishUnfinished() async
    /// The subscription's original transaction id, which the server links to the account.
    func originalTransactionId() async -> String?
}

/// StoreKit 2.
public struct AppStoreCloudStore: CloudStore {
    public init() {}

    private func product() async -> Product? { try? await Product.products(for: [CloudFeature.productID]).first }

    public func offer() async -> CloudModel.Offer? {
        await product().map { CloudModel.Offer(name: $0.displayName, price: $0.displayPrice) }
    }

    public func hasEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == CloudFeature.productID, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    public func purchase(token: UUID) async throws -> Bool {
        guard let product = await product() else { throw CloudModel.Unavailable() }
        await finishUnfinished()
        guard case .success(let verification) = try await product.purchase(options: [.appAccountToken(token)]),
              case .verified(let transaction) = verification else { return false }
        await transaction.finish()
        // An old renewal handed back instead of a new purchase has already expired.
        return transaction.expirationDate.map { $0 > .now } ?? true
    }

    public func sync() async throws { try await AppStore.sync() }

    public func finishUnfinished() async {
        for await result in Transaction.unfinished where result.unsafePayloadValue.productID == CloudFeature.productID {
            await result.unsafePayloadValue.finish()
        }
    }

    public func originalTransactionId() async -> String? {
        var latest: Transaction?
        for await result in Transaction.all {
            if case .verified(let transaction) = result, transaction.productID == CloudFeature.productID {
                if latest == nil || transaction.purchaseDate > latest!.purchaseDate { latest = transaction }
            }
        }
        return latest.map { String($0.originalID) }
    }
}

/// Fernsy Cloud as the apps show it (add-recording-cloud, cloud-account-from-icloud-key): the
/// subscription (StoreKit), the account that comes from the cloud key without any prompt, the
/// list of cloud recordings and the player source for one. Shared by the Mac, iOS and Apple TV.
@MainActor
@Observable
public final class CloudModel {
    public enum Phase: Equatable { case idle, loading, failed(String) }
    public struct Offer: Equatable, Sendable {
        public var name: String
        public var price: String
    }
    struct Unavailable: Error {}

    /// StoreKit says an entitlement is current (or the dev server stands in for it).
    public private(set) var hasSubscription = false
    public private(set) var offer: Offer?
    public private(set) var account: CloudClient.Account?
    public private(set) var items: [CloudRecordingItem] = []
    public private(set) var phase: Phase = .idle
    /// What iCloud said about the key; nil before the first look.
    public private(set) var keyState: CloudKeyLookup?
    public private(set) var isPurchasing = false
    /// The subscription belongs to another account (or to none): offer to move it (design E).
    public private(set) var canMoveSubscription = false
    /// Whether Fernsy on a Mac is known in iCloud; nil before the first look (design F).
    public private(set) var macPresence: CloudMacPresence?

    @ObservationIgnored public let client: CloudClient
    @ObservationIgnored public let keys: CloudKeyStore
    @ObservationIgnored public let library: CloudLibrary
    @ObservationIgnored private let store: CloudStore
    @ObservationIgnored private var updates: Task<Void, Never>?

    public init(client: CloudClient = .live(), keys: CloudKeyStore = .live(), store: CloudStore = AppStoreCloudStore()) {
        self.client = client
        self.keys = keys
        self.store = store
        self.library = CloudLibrary(source: client, keys: keys)
    }

    public var hasKey: Bool { if case .found = keyState { true } else { false } }
    /// Why a subscriber's device has no account: the key is locked, or not on it yet.
    public var missingKeyText: String {
        Self.describe(keyState == .locked ? CloudKeyStore.Locked() as Error : CloudClient.Failure.noAccount)
    }
    /// A key (or the dev token) gives this device its account.
    public var hasAccount: Bool { client.hasAccount }
    /// Cloud places beyond the offer show.
    public var canUseCloud: Bool { hasSubscription || (account?.canPlay ?? false) }
    public var canUpload: Bool { hasAccount && (account?.canUpload ?? false) }
    /// iPad, iPhone and Apple TV offer the subscription only when a Mac records (spec: Offer
    /// only with a Mac); subscribers always see their account.
    public var mayOffer: Bool { macPresence == .known }

    /// Launch: subscription, key and, with both, the account and list.
    public func start() async {
        if updates == nil, store is AppStoreCloudStore {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    // Renewals, refunds and purchases from other devices: finished, or the next
                    // purchase gets one of them back instead of the App Store's sheet.
                    if result.unsafePayloadValue.productID == CloudFeature.productID { await result.unsafePayloadValue.finish() }
                    await self?.refreshSubscription()
                }
            }
        }
        await store.finishUnfinished()
        await connect()
        await refreshSubscription()
        if hasAccount && (hasSubscription || client.isDevelopment) { await refresh() }
        if hasSubscription, !client.isDevelopment, account?.state != .active { await linkSubscription() }
    }

    /// Looks up the key (never creates one) and hands it to the client.
    public func connect() async {
        let lookup = await keys.lookup()
        keyState = lookup
        if case .found(let key) = lookup { client.use(key) }
    }

    /// On iPad, iPhone and Apple TV before the offer.
    public func refreshMacPresence() async {
        macPresence = await keys.macPresence()
    }

    // MARK: Subscription

    public func refreshSubscription() async {
        if client.isDevelopment {
            hasSubscription = (try? await client.account().canPlay) ?? false
            return
        }
        hasSubscription = await store.hasEntitlement()
        if offer == nil { offer = await store.offer() }
    }

    /// The key for subscribing: the existing one, or a new one when iCloud has none (design D),
    /// registered with the server before the purchase (design B).
    private func accountKey() async -> CloudAccountKey? {
        do {
            let key = try await keys.createIfMissing()
            keyState = .found(key)
            client.use(key)
            if !client.isDevelopment { _ = try await client.account() }
            return key
        } catch {
            phase = .failed(Self.describe(error))
            if error is CloudKeyStore.Locked { keyState = .locked }
            return nil
        }
    }

    /// Buys the subscription for this key's account (design C); true when it is active afterwards.
    @discardableResult
    public func purchase() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        guard let key = await accountKey(), let token = UUID(uuidString: key.accountId) else { return false }
        do {
            if try await store.purchase(token: token) {
                await refreshSubscription()
                if !hasSubscription {
                    phase = .failed(String(localized: "The App Store did not confirm the subscription. Please try again.", bundle: .module))
                }
            }
        } catch is Unavailable {
            phase = .failed(String(localized: "The subscription is not available right now.", bundle: .module))
        } catch {
            phase = .failed(error.localizedDescription)
        }
        await refreshSubscription()
        if hasSubscription { await linkSubscription() }
        return hasSubscription
    }

    @discardableResult
    public func restore() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        try? await store.sync()
        await refreshSubscription()
        if hasSubscription, await accountKey() != nil { await linkSubscription() }
        return hasSubscription
    }

    /// Takes over a subscription that belongs to another account or to none (design E).
    public func moveSubscription() async {
        await linkSubscription(move: true)
    }

    private func linkSubscription(move: Bool = false) async {
        guard !client.isDevelopment, hasAccount, let id = await store.originalTransactionId() else { return }
        do {
            account = try await client.linkSubscription(originalTransactionId: id, move: move)
            canMoveSubscription = false
            if move { AppLog.info(.app, "Fernsy Cloud: subscription moved to this key") }
            await refresh()
        } catch CloudClient.Failure.otherAccount {
            canMoveSubscription = true
        } catch {
            AppLog.warning(.app, "Fernsy Cloud: could not link the subscription: \(error)")
        }
    }

    // MARK: Account and recordings

    public func refresh() async {
        guard hasAccount else { return }
        phase = .loading
        do {
            account = try await client.account()
            if client.isDevelopment { hasSubscription = account?.canPlay ?? false }
            if keyState == nil || !hasKey { keyState = await keys.lookup() }
            items = (account?.canPlay ?? false) ? try await library.items() : []
            phase = .idle
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// "Delete Fernsy Cloud data" (design G): every recording and the account on the server.
    /// The subscription stays and comes back to this key with the next request.
    public func deleteCloudData() async throws {
        try await client.deleteAccount()
        for item in items { library.forget(item.id) }
        items = []
        account = try? await client.account()
        AppLog.info(.app, "Fernsy Cloud: all cloud data deleted")
    }

    public func delete(_ item: CloudRecordingItem) async throws {
        try await client.delete(id: item.id)
        library.forget(item.id)
        items.removeAll { $0.id == item.id }
        account = try? await client.account()
        AppLog.info(.app, "Fernsy Cloud: deleted \(item.id.prefix(8))")
    }

    /// Everything a player needs for one recording: the signed URL and the file key.
    public func playback(for item: CloudRecordingItem) async throws -> (dataURL: URL, meta: CloudRecordingMeta) {
        guard let meta = item.meta else { throw CloudCrypto.Failure.unknownKey("") }
        let urls = try await client.readURLs(id: item.id)
        return (urls.dataURL, meta)
    }

    public static func describe(_ error: Error) -> String {
        switch error as? CloudClient.Failure {
        case .noAccount?: String(localized: "This device does not have the key for Fernsy Cloud yet. It comes from iCloud of the same Apple ID.", bundle: .module)
        case .accountConflict?: String(localized: "Fernsy Cloud does not accept this device’s key. Please contact support.", bundle: .module)
        case .noSubscription?: String(localized: "Fernsy Cloud needs an active subscription.", bundle: .module)
        case .network?: String(localized: "Fernsy Cloud cannot be reached.", bundle: .module)
        case .appleNotConfigured?: String(localized: "Fernsy Cloud is not ready yet.", bundle: .module)
        case .quota(let needed, let free)?:
            String(localized: "Not enough Fernsy Cloud storage: \(CloudUploadQueue.bytes(needed)) needed, \(CloudUploadQueue.bytes(free)) free.", bundle: .module)
        default:
            error is CloudKeyStore.Locked
                ? String(localized: "iCloud cannot be reached, so Fernsy Cloud is not available right now.", bundle: .module)
                : error.localizedDescription
        }
    }

    /// The subscription line in Settings: "Aktiv, verlängert sich am …", "Abgelaufen am …".
    public static func stateText(_ account: CloudClient.Account) -> String {
        switch account.state {
        case .active:
            if let expires = account.expiresAt {
                return String(localized: "Active, renews \(expires.formatted(date: .abbreviated, time: .omitted))", bundle: .module)
            }
            return String(localized: "Active", bundle: .module)
        case .grace:
            return String(localized: "Ended \(account.endedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")", bundle: .module)
        case .ended, .none:
            return String(localized: "No subscription", bundle: .module)
        }
    }

    /// "Used of total": the storage line in Settings.
    public static func storageText(_ account: CloudClient.Account) -> String {
        let used = ByteCountFormatter.string(fromByteCount: account.usedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: account.totalBytes, countStyle: .file)
        return String(localized: "\(used) of \(total) used", bundle: .module)
    }

    /// "Wird am … gelöscht": the grace period's end, for the notes in Settings and lists.
    public var deletionNote: String? {
        guard let account, account.state == .grace, let deleteAt = account.deleteAt else { return nil }
        let days = max(0, Int((deleteAt.timeIntervalSinceNow / 86400).rounded(.up)))
        return String(localized: "Your subscription has ended. Cloud recordings are deleted in \(days) days unless you renew.", bundle: .module)
    }
}
