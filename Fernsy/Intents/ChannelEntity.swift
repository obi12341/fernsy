import AppIntents
import CoreSpotlight

/// A live channel for Siri, Spotlight and Shortcuts. Only channels the app shows are offered
/// (hidden ones and adult content per Settings left out).
struct ChannelEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sender")
    static let defaultQuery = ChannelQuery()

    let id: Int
    let name: String
    let category: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: category.map { "\($0)" })
    }

    @MainActor
    init(_ channel: LiveChannel, app: AppModel) {
        id = channel.id
        name = channel.displayName
        category = app.liveCategories.first { $0.id == channel.categoryId }?.displayName
    }
}

struct ChannelQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [ChannelEntity] {
        guard let app = await IntentSupport.app() else { return [] }
        let actions = FernsyActions(app: app)
        return identifiers.compactMap { actions.visibleChannel($0) }.map { ChannelEntity($0, app: app) }
    }

    /// Exact names first, then names starting with the text, then names containing it.
    @MainActor
    func entities(matching string: String) async throws -> [ChannelEntity] {
        guard let app = await IntentSupport.app() else { return [] }
        let needle = makeSearchKey(string.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return [] }
        let matches = FernsyActions(app: app).visibleChannels.compactMap { channel -> (Int, LiveChannel)? in
            let name = makeSearchKey(channel.displayName)
            if name == needle { return (0, channel) }
            if name.hasPrefix(needle) { return (1, channel) }
            if channel.searchKey.contains(needle) { return (2, channel) }
            return nil
        }
        return matches.sorted { $0.0 < $1.0 }.prefix(20).map { ChannelEntity($0.1, app: app) }
    }

    /// Favourites and recently watched: also the values Siri knows for the App Shortcut phrases.
    @MainActor
    func suggestedEntities() async throws -> [ChannelEntity] {
        guard let app = await IntentSupport.app() else { return [] }
        return FernsyActions(app: app).favoritesAndRecent().map { ChannelEntity($0, app: app) }
    }
}

/// Shared helpers for the intents.
@MainActor
enum IntentSupport {
    /// The app model, once the catalog is there (Siri may have just launched Fernsy).
    static func app() async -> AppModel? {
        for _ in 0..<50 {
            if let app = AppDelegate.app, app.credentials == nil || !app.channels.isEmpty { return app }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return AppDelegate.app
    }

    nonisolated static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// "heute 20:15", "morgen 08:00" or the date.
    nonisolated static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "heute \(time(date))") }
        if calendar.isDateInTomorrow(date) { return String(localized: "morgen \(time(date))") }
        return date.formatted(.dateTime.weekday(.wide).day().month().hour().minute())
    }
}

/// Keeps the visible channels in Spotlight's semantic index for Siri. Rebuilt (debounced) when
/// the catalog, the hidden channels or the adult settings change; cleared on sign-out.
@MainActor
enum SiriIndex {
    private static var pending: Task<Void, Never>?
    private static var indexed: Int?

    static var isEnabled: Bool {
        #if DEBUG
        // Debug builds share the user's Spotlight: they index only with IPTV_SIRIINDEX=1.
        return ProcessInfo.processInfo.environment["IPTV_SIRIINDEX"] == "1"
        #else
        return true
        #endif
    }

    static func schedule(_ app: AppModel) {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            let channels = FernsyActions(app: app).visibleChannels
            let signature = channels.map(\.id).hashValue ^ channels.count
            guard signature != indexed else { return }
            indexed = signature
            let entities = channels.map { ChannelEntity($0, app: app) }
            do {
                try await CSSearchableIndex.default().deleteAppEntities(ofType: ChannelEntity.self)
                for start in stride(from: 0, to: entities.count, by: 1000) {
                    try await CSSearchableIndex.default().indexAppEntities(Array(entities[start..<min(start + 1000, entities.count)]))
                }
                AppLog.info(.app, "Siri: \(entities.count) channels indexed")
            } catch {
                AppLog.warning(.app, "Siri: indexing failed: \(error.localizedDescription)")
            }
            FernsyShortcuts.updateAppShortcutParameters()
        }
    }

    static func clear() {
        guard isEnabled else { return }
        pending?.cancel()
        indexed = nil
        Task { try? await CSSearchableIndex.default().deleteAppEntities(ofType: ChannelEntity.self) }
    }
}
