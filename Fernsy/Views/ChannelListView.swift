import SwiftUI

extension AppModel {
    func hiddenCategoryIDs(_ categories: [XCategory]) -> Set<String> {
        showAdult ? [] : Set(categories.filter(isAdultCategory).map(\.id))
    }

    func filteredChannels(categoryID: String, query: String) -> [LiveChannel] {
        let hidden = hiddenCategoryIDs(liveCategories)
        var list = categoryID == allCategoryID ? channels : (channelsByCategory[categoryID] ?? [])
        if !showAdult { list = list.filter { !$0.isAdult && !hidden.contains($0.categoryId ?? "") } }
        let needle = makeSearchKey(query)
        if !needle.isEmpty { list = list.filter { $0.searchKey.contains(needle) } }
        return list
    }
}

struct ChannelListView: View {
    @EnvironmentObject private var app: AppModel
    let categoryID: String
    let query: String

    @State private var selection: Int?

    var body: some View {
        let channels = app.filteredChannels(categoryID: categoryID, query: query)
        List(selection: $selection) {
            ForEach(channels) { channel in
                ChannelRow(channel: channel, isPlaying: isPlaying(channel))
                    .tag(channel.id)
            }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            if let id = ids.first, let channel = app.channel(id) {
                Button("Abspielen") { app.play(channel) }
                Button(app.isFavorite("live:\(id)") ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                    app.toggleFavorite("live:\(id)")
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let channel = app.channel(id) { app.play(channel) }
        }
        .safeAreaInset(edge: .bottom) {
            if let id = selection, let channel = app.channel(id) {
                EPGPanel(channel: channel, epg: app.epg)
            }
        }
        .overlay {
            if channels.isEmpty && !app.channels.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Live TV")
        .navigationSubtitle("\(channels.count) Sender")
        #if DEBUG
        .task {
            // Screenshot runs: IPTV_SELECT=<channel id> shows that channel's programme panel.
            if let id = ProcessInfo.processInfo.environment["IPTV_SELECT"].flatMap(Int.init) { selection = id }
        }
        #endif
    }

    private func isPlaying(_ channel: LiveChannel) -> Bool {
        if case .live(let id, _)? = app.nowPlaying?.kind { return id == channel.id }
        return false
    }
}

struct ChannelRow: View {
    @EnvironmentObject private var app: AppModel
    let channel: LiveChannel
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: channel.icon, maxPixel: 96, contentMode: .fit) {
                Image(systemName: "tv").foregroundStyle(.tertiary)
            }
            .frame(width: 48, height: 30)

            Text(channel.name)
                .lineLimit(1)
                .fontWeight(isPlaying ? .semibold : .regular)

            Spacer()

            if isPlaying {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
            }
            if channel.hasArchive {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary).help("Archiv verfügbar")
            }
            Button {
                app.toggleFavorite("live:\(channel.id)")
            } label: {
                Image(systemName: app.isFavorite("live:\(channel.id)") ? "star.fill" : "star")
                    .foregroundStyle(app.isFavorite("live:\(channel.id)") ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

/// Now/next for the selected channel.
struct EPGPanel: View {
    @EnvironmentObject private var app: AppModel
    let channel: LiveChannel
    @ObservedObject private var guide: ChannelGuide

    init(channel: LiveChannel, epg: EPGStore) {
        self.channel = channel
        guide = epg.guide(channel.id)
    }

    var body: some View {
        let entries = (guide.entries ?? []).filter { $0.end > Date() }
        let loaded = guide.entries != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(channel.name).font(.headline).lineLimit(1)
                Spacer()
                if let now = entries.first(where: { $0.start <= Date() && $0.end > Date() }) {
                    RecordButton(channel: channel, entry: now)
                        .controlSize(.small)
                }
                Button("Abspielen", systemImage: "play.fill") { app.play(channel) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            if let now = entries.first(where: { $0.start <= Date() && $0.end > Date() }) ?? entries.first {
                EPGLine(entry: now, highlight: true)
                    .contextMenu { RecordButton(channel: channel, entry: now) }
                ForEach(entries.filter { $0.start >= now.end }.prefix(2)) { entry in
                    EPGLine(entry: entry, highlight: false)
                        .contextMenu { RecordButton(channel: channel, entry: entry) }
                }
            } else if loaded {
                Text("Keine Programminformationen").foregroundStyle(.secondary).font(.callout)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
        .background(.bar)
        .task(id: channel.id) { await app.epg.load(channel.id, client: app.client) }
    }
}

struct EPGLine: View {
    let entry: EPGEntry
    let highlight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.start.formatted(date: .omitted, time: .shortened)) – \(entry.end.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(entry.title).fontWeight(highlight ? .semibold : .regular).lineLimit(1)
            }
            .font(.callout)
            if highlight {
                ProgressView(value: entry.progress).progressViewStyle(.linear).tint(.accentColor)
                if !entry.description.isEmpty {
                    Text(entry.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}
