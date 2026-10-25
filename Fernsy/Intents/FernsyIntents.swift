import AppIntents
import SwiftUI

/// A show from the guide: "<channel id>:<start epoch>", the same id the MCP tools use.
struct ShowEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sendung")
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
        IntentAnswer(text: String(localized: "Melde dich zuerst in Fernsy bei deinem IPTV-Konto an."))
    }

    static func play(channelId: Int) async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        guard let channel = actions.visibleChannel(channelId) else {
            return IntentAnswer(text: String(localized: "Diesen Sender gibt es in Fernsy nicht."))
        }
        switch actions.playChannel(channel) {
        case .playing:
            return IntentAnswer(text: String(localized: "Fernsy zeigt jetzt \(channel.displayName)."))
        case .blocked(let recording):
            return IntentAnswer(text: String(localized: "Gerade wird „\(recording.title)“ auf \(recording.channelName) aufgenommen, und dein Zugang erlaubt nur \(app.tuners.limit) Stream(s). Fernsy schaltet deshalb nicht um."))
        }
    }

    static func whatsOn() async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        let channels = actions.favoritesAndRecent(limit: 12)
        guard !channels.isEmpty else {
            return IntentAnswer(text: String(localized: "Markiere in Fernsy Sender als Favoriten, dann sage ich dir, was dort läuft."))
        }
        await actions.loadGuides(channels.map(\.id), timeout: 10)
        let rows = channels.compactMap { channel -> (title: String, detail: String)? in
            guard let current = actions.nowAndNext(channel.id).now else { return nil }
            return (channel.displayName, String(localized: "\(current.title) · bis \(IntentSupport.time(current.end))"))
        }
        guard !rows.isEmpty else { return IntentAnswer(text: String(localized: "Für deine Favoriten gibt es gerade keine Programmdaten.")) }
        let spoken = rows.prefix(3).map { "\($0.title): \($0.detail.components(separatedBy: " · ").first ?? $0.detail)" }.joined(separator: ", ")
        return IntentAnswer(text: String(localized: "Gerade läuft \(spoken)."), rows: rows)
    }

    static func findShow(_ query: String) async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        let channels = actions.favoritesAndRecent()
        guard !channels.isEmpty else {
            return IntentAnswer(text: String(localized: "Markiere in Fernsy Sender als Favoriten, dann suche ich dort im Programm."))
        }
        let hits = await actions.searchGuide(query, on: channels).prefix(8)
        guard let first = hits.first else {
            return IntentAnswer(text: String(localized: "„\(query)“ habe ich im Programm deiner Favoriten und zuletzt gesehenen Sender nicht gefunden."))
        }
        let rows = hits.map { (title: $0.entry.title, detail: "\($0.channel.displayName) · \(IntentSupport.when($0.entry.start))") }
        return IntentAnswer(text: String(localized: "„\(first.entry.title)“ kommt \(IntentSupport.when(first.entry.start)) auf \(first.channel.displayName)."),
                            rows: rows, shows: hits.map { ShowEntity($0.entry, on: $0.channel) })
    }

    /// Records the show on now on `channelId`, or on the channel the player shows.
    static func recordNow(channelId: Int?) async -> IntentAnswer {
        guard let app = await IntentSupport.app(), app.credentials != nil else { return notSignedIn }
        let actions = FernsyActions(app: app)
        guard let channel = channelId.flatMap(actions.visibleChannel) ?? actions.playingChannel else {
            return IntentAnswer(text: String(localized: "Sag mir den Sender, oder schalte ihn zuerst in Fernsy ein."))
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
            return IntentAnswer(text: String(localized: "Diese Sendung finde ich nicht mehr im Programm."))
        }
        await actions.loadGuides([channelId], timeout: 8)
        guard let entry = actions.entries(channelId).first(where: { abs($0.start.timeIntervalSince1970 - epoch) < 60 }), entry.end > Date() else {
            return IntentAnswer(text: String(localized: "Diese Sendung finde ich nicht mehr im Programm."))
        }
        return answer(actions.schedule(entry, on: channel), title: entry.title)
    }

    private static func answer(_ result: FernsyActions.ScheduleResult, title: String) -> IntentAnswer {
        switch result {
        case .refused(let reason):
            return IntentAnswer(text: reason)
        case .planned(let recording, _):
            guard let recording else { return IntentAnswer(text: String(localized: "„\(title)“ wird aufgenommen.")) }
            return IntentAnswer(text: String(localized: "„\(recording.title)“ wird aufgenommen, \(IntentSupport.when(recording.recordStart)) bis \(IntentSupport.time(recording.recordEnd))."))
        }
    }

    static func stop() async -> IntentAnswer {
        guard let app = await IntentSupport.app() else { return notSignedIn }
        return FernsyActions(app: app).stopPlayback()
            ? IntentAnswer(text: String(localized: "Fernsy hat die Wiedergabe beendet."))
            : IntentAnswer(text: String(localized: "In Fernsy läuft gerade nichts."))
    }
}

// MARK: Intents

struct PlayChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Sender einschalten"
    static let description = IntentDescription("Zeigt einen Live-Sender in Fernsy.")

    @Parameter(title: "Sender")
    var channel: ChannelEntity

    init() {}
    init(channel: ChannelEntity) { self.channel = channel }

    static var parameterSummary: some ParameterSummary { Summary("Schalte auf \(\.$channel)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentActions.play(channelId: channel.id).text))
    }
}

struct WhatsOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Was läuft gerade"
    static let description = IntentDescription("Sagt, was gerade auf deinen Lieblingssendern läuft.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let answer = await IntentActions.whatsOn()
        return .result(dialog: IntentDialog(stringLiteral: answer.text), view: IntentRowsView(rows: answer.rows))
    }
}

struct FindShowIntent: AppIntent {
    static let title: LocalizedStringResource = "Sendung suchen"
    static let description = IntentDescription("Sucht eine Sendung im Programm deiner Favoriten und zuletzt gesehenen Sender.")

    @Parameter(title: "Sendung")
    var query: String

    static var parameterSummary: some ParameterSummary { Summary("Suche \(\.$query) im Programm") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView & ReturnsValue<[ShowEntity]> {
        let answer = await IntentActions.findShow(query)
        return .result(value: answer.shows, dialog: IntentDialog(stringLiteral: answer.text), view: IntentRowsView(rows: answer.rows))
    }
}

struct RecordIntent: AppIntent {
    static let title: LocalizedStringResource = "Laufende Sendung aufnehmen"
    static let description = IntentDescription("Nimmt die Sendung auf, die gerade auf dem Sender läuft – ohne Angabe auf dem Sender im Player.")

    @Parameter(title: "Sender")
    var channel: ChannelEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentActions.recordNow(channelId: channel?.id).text))
    }
}

struct RecordShowIntent: AppIntent {
    static let title: LocalizedStringResource = "Sendung aufnehmen"
    static let description = IntentDescription("Plant die Aufnahme einer Sendung aus dem Programm.")

    @Parameter(title: "Sendung")
    var show: ShowEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentActions.record(showId: show.id).text))
    }
}

struct StopPlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Wiedergabe beenden"
    static let description = IntentDescription("Beendet die Wiedergabe in Fernsy.")

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
            "Schalte \(.applicationName) auf \(\.$channel)",
            "\(.applicationName) auf \(\.$channel)",
            "Zeig \(\.$channel) in \(.applicationName)",
        ], shortTitle: "Sender einschalten", systemImageName: "tv")
        AppShortcut(intent: WhatsOnIntent(), phrases: [
            "Was läuft gerade in \(.applicationName)",
            "Was läuft in \(.applicationName)",
        ], shortTitle: "Was läuft gerade", systemImageName: "list.bullet.rectangle")
        AppShortcut(intent: FindShowIntent(), phrases: [
            "Suche eine Sendung in \(.applicationName)",
            "Wann kommt etwas in \(.applicationName)",
        ], shortTitle: "Sendung suchen", systemImageName: "magnifyingglass")
        AppShortcut(intent: RecordIntent(), phrases: [
            "Nimm das in \(.applicationName) auf",
            "Nimm \(\.$channel) in \(.applicationName) auf",
            "Aufnahme in \(.applicationName) starten",
        ], shortTitle: "Aufnehmen", systemImageName: "record.circle")
        AppShortcut(intent: StopPlaybackIntent(), phrases: [
            "Stopp \(.applicationName)",
            "Beende die Wiedergabe in \(.applicationName)",
        ], shortTitle: "Wiedergabe beenden", systemImageName: "stop.circle")
    }
}
