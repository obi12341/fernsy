import AppIntents
import SwiftUI

/// A show from the guide: "<channel id>:<start epoch>", the same id the MCP tools use.
struct ShowEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Show")
    static let defaultQuery = ShowQuery()

    let id: String
    let title: String
    let channelId: Int
    let channel: String
    let start: Date
    let end: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(channel) · \(IntentSupport.when(start))")
    }

    init(_ entry: EPGEntry, on channel: LiveChannel) {
        id = "\(channel.id):\(Int(entry.start.timeIntervalSince1970))"
        title = entry.title
        channelId = channel.id
        self.channel = channel.displayName
        start = entry.start
        end = entry.end
    }
}

struct ShowQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ShowEntity] {
        guard let app = await IntentSupport.app() else { return [] }
        let actions = FernsyActions(app: app)
        var result: [ShowEntity] = []
        for id in identifiers {
            let parts = id.split(separator: ":")
            guard parts.count == 2, let channelId = Int(parts[0]), let epoch = Double(parts[1]),
                  let channel = actions.visibleChannel(channelId) else { continue }
            await actions.loadGuides([channelId], timeout: 8)
            if let entry = actions.entries(channelId).first(where: { abs($0.start.timeIntervalSince1970 - epoch) < 60 }) {
                result.append(ShowEntity(entry, on: channel))
            }
        }
        return result
    }
}

/// What an intent answers: the spoken sentence and, for lists, the rows of the snippet.
struct IntentAnswer {
    var text: String
    var rows: [(title: String, detail: String)] = []
    var shows: [ShowEntity] = []
}

/// The actions behind the intents, callable without the system (debug hook `IPTV_TESTINTENT`).
@MainActor
enum IntentActions {
    private static var notSignedIn: IntentAnswer {
        IntentAnswer(text: String(localized: "First sign in to your IPTV account in Fernsy."))
    }

    static func play(channelId: Int) async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        guard let channel = actions.visibleChannel(channelId) else {
            return IntentAnswer(text: String(localized: "Fernsy doesn't have this channel."))
        }
        switch actions.playChannel(channel) {
        case .playing:
            return IntentAnswer(text: String(localized: "Fernsy is now showing \(channel.displayName)."))
        case .blocked(let recording):
            return IntentAnswer(text: String(localized: "\"\(recording.title)\" is being recorded on \(recording.channelName), and your account allows only \(app.tuners.limit) stream(s). So Fernsy doesn't switch."))
        }
    }

    static func whatsOn() async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        let channels = actions.favoritesAndRecent(limit: 12)
        guard !channels.isEmpty else {
            return IntentAnswer(text: String(localized: "Mark channels as favorites in Fernsy, and I'll tell you what's on."))
        }
        await actions.loadGuides(channels.map(\.id), timeout: 10)
        let rows = channels.compactMap { channel -> (title: String, detail: String)? in
            guard let current = actions.nowAndNext(channel.id).now else { return nil }
            return (channel.displayName, String(localized: "\(current.title) · until \(IntentSupport.time(current.end))"))
        }
        guard !rows.isEmpty else { return IntentAnswer(text: String(localized: "There is no program data for your favorites right now.")) }
        let spoken = rows.prefix(3).map { "\($0.title): \($0.detail.components(separatedBy: " · ").first ?? $0.detail)" }.joined(separator: ", ")
        return IntentAnswer(text: String(localized: "On now: \(spoken)."), rows: rows)
    }

    static func findShow(_ query: String) async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        let channels = actions.favoritesAndRecent()
        guard !channels.isEmpty else {
            return IntentAnswer(text: String(localized: "Mark channels as favorites in Fernsy, and I'll search their guide."))
        }
        let hits = await actions.searchGuide(query, on: channels).prefix(8)
        guard let first = hits.first else {
            return IntentAnswer(text: String(localized: "I didn't find \"\(query)\" in the guide of your favorite and recently watched channels."))
        }
        let rows = hits.map { (title: $0.entry.title, detail: "\($0.channel.displayName) · \(IntentSupport.when($0.entry.start))") }
        return IntentAnswer(text: String(localized: "\"\(first.entry.title)\" is on \(IntentSupport.when(first.entry.start)) on \(first.channel.displayName)."),
                            rows: rows, shows: hits.map { ShowEntity($0.entry, on: $0.channel) })
    }

    /// Records the show on now on `channelId`, or on the channel the player shows.
    static func recordNow(channelId: Int?) async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        guard let channel = channelId.flatMap(actions.visibleChannel) ?? actions.playingChannel else {
            return IntentAnswer(text: String(localized: "Tell me the channel, or switch to it in Fernsy first."))
        }
        let (result, show) = await actions.recordNow(channel)
        return answer(result, title: show?.title ?? channel.displayName)
    }

    static func record(showId: String) async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        let parts = showId.split(separator: ":")
        guard parts.count == 2, let channelId = Int(parts[0]), let epoch = Double(parts[1]),
              let channel = actions.visibleChannel(channelId) else {
            return IntentAnswer(text: String(localized: "I can't find this show in the guide any more."))
        }
        await actions.loadGuides([channelId], timeout: 8)
        guard let entry = actions.entries(channelId).first(where: { abs($0.start.timeIntervalSince1970 - epoch) < 60 }), entry.end > Date() else {
            return IntentAnswer(text: String(localized: "I can't find this show in the guide any more."))
        }
        return answer(actions.schedule(entry, on: channel), title: entry.title)
    }

    private static func answer(_ result: FernsyActions.ScheduleResult, title: String) -> IntentAnswer {
        switch result {
        case .refused(let reason):
            return IntentAnswer(text: reason)
        case .planned(let recording, _):
            guard let recording else { return IntentAnswer(text: String(localized: "\"\(title)\" will be recorded.")) }
            return IntentAnswer(text: String(localized: "\"\(recording.title)\" will be recorded, \(IntentSupport.when(recording.recordStart)) to \(IntentSupport.time(recording.recordEnd))."))
        }
    }

    /// Shows `text` in the library's toolbar search.
    static func search(_ text: String) -> IntentAnswer {
        guard let app = AppDelegate.app else { return notSignedIn }
        app.requestedSearch = text
        PlayerWindow.showLibrary()
        return IntentAnswer(text: String(localized: "Fernsy is searching for \"\(text)\"."))
    }

    static func stop() async -> IntentAnswer {
        guard let app = await IntentSupport.app() else { return notSignedIn }
        return FernsyActions(app: app).stopPlayback()
            ? IntentAnswer(text: String(localized: "Fernsy stopped playback."))
            : IntentAnswer(text: String(localized: "Nothing is playing in Fernsy."))
    }
}

// MARK: Siri AI schemas

/// "Öffne ZDF in Fernsy": opening a live channel means watching it.
@AppIntent(schema: .system.open)
struct OpenChannelIntent: OpenIntent {
    var target: ChannelEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentActions.play(channelId: target.id).text))
    }
}

/// "Suche Tatort in Fernsy": the library's search over channels, films, series, recordings
/// and Jellyfin.
@AppIntent(schema: .system.searchInApp)
struct SearchFernsyIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = IntentActions.search(criteria.term)
        return .result()
    }
}

// MARK: Intents

struct PlayChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Channel"
    static let description = IntentDescription("Shows a live channel in Fernsy.")

    @Parameter(title: "Channels")
    var channel: ChannelEntity

    init() {}
    init(channel: ChannelEntity) { self.channel = channel }

    static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$channel)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentActions.play(channelId: channel.id).text))
    }
}

struct WhatsOnIntent: AppIntent {
    static let title: LocalizedStringResource = "What's On"
    static let description = IntentDescription("Tells you what's on now on your favorite channels.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let answer = await IntentActions.whatsOn()
        return .result(dialog: IntentDialog(stringLiteral: answer.text), view: IntentRowsView(rows: answer.rows))
    }
}

struct FindShowIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Show"
    static let description = IntentDescription("Searches the guide of your favorite and recently watched channels for a show.")

    @Parameter(title: "Show")
    var query: String

    static var parameterSummary: some ParameterSummary { Summary("Find \(\.$query) in the guide") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView & ReturnsValue<[ShowEntity]> {
        let answer = await IntentActions.findShow(query)
        return .result(value: answer.shows, dialog: IntentDialog(stringLiteral: answer.text), view: IntentRowsView(rows: answer.rows))
    }
}

struct RecordIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Current Show"
    static let description = IntentDescription("Records the show on now on the channel – without a channel, on the one in the player.")

    @Parameter(title: "Channels")
    var channel: ChannelEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentActions.recordNow(channelId: channel?.id).text))
    }
}

struct RecordShowIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Show"
    static let description = IntentDescription("Schedules a recording of a show from the guide.")

    @Parameter(title: "Show")
    var show: ShowEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentActions.record(showId: show.id).text))
    }
}

struct StopPlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Playback"
    static let description = IntentDescription("Stops playback in Fernsy.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentActions.stop().text))
    }
}

/// The list Siri shows under the answer.
struct IntentRowsView: View {
    let rows: [(title: String, detail: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.title).font(.headline)
                    Text(verbatim: row.detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: App Shortcuts

struct FernsyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayChannelIntent(), phrases: [
            "Switch \(.applicationName) to \(\.$channel)",
            "\(.applicationName) on \(\.$channel)",
            "Show \(\.$channel) in \(.applicationName)",
        ], shortTitle: "Switch Channel", systemImageName: "tv")
        AppShortcut(intent: WhatsOnIntent(), phrases: [
            "What's on in \(.applicationName)",
            "What's on now in \(.applicationName)",
        ], shortTitle: "What's On", systemImageName: "list.bullet.rectangle")
        AppShortcut(intent: FindShowIntent(), phrases: [
            "Find a show in \(.applicationName)",
            "When is something on in \(.applicationName)",
        ], shortTitle: "Find Show", systemImageName: "magnifyingglass")
        AppShortcut(intent: RecordIntent(), phrases: [
            "Record this in \(.applicationName)",
            "Record \(\.$channel) in \(.applicationName)",
            "Start recording in \(.applicationName)",
        ], shortTitle: "Record", systemImageName: "record.circle")
        AppShortcut(intent: StopPlaybackIntent(), phrases: [
            "Stop \(.applicationName)",
            "Stop playback in \(.applicationName)",
        ], shortTitle: "Stop Playback", systemImageName: "stop.circle")
    }
}
