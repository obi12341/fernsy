import FernsyCore
import FernsyPlayer
import SwiftUI

extension AppModel {
    func hiddenCategoryIDs(_ categories: [XCategory]) -> Set<String> {
        showAdult ? [] : Set(categories.filter(isAdultCategory).map(\.id))
    }

    /// `includeHidden`: also the channels the user has hidden (Edit mode).
    func filteredChannels(categoryID: String, query: String, includeHidden: Bool = false) -> [LiveChannel] {
        var list: [LiveChannel]
        switch categoryID {
        case allCategoryID: list = channels
        case favoriteChannelsID: list = channels.filter { isFavorite("live:\($0.id)") }
        case recentChannelsID: list = recentChannels.compactMap(channel)
        default: list = channelsByCategory[categoryID] ?? []
        }
        // Adult channels: hidden everywhere unless shown, and in "Zuletzt gesehen" unless allowed there too.
        if !showAdult || (categoryID == recentChannelsID && !showAdultInRecent) {
            let adultCategories = Set(liveCategories.filter(isAdultCategory).map(\.id))
            list = list.filter { !isAdult($0, adultCategories: adultCategories) }
        }
        if !includeHidden { list = list.filter { !isHidden($0) } }
        let needle = makeSearchKey(query)
        if !needle.isEmpty { list = list.filter { $0.searchKey.contains(needle) } }
        return list
    }
}

struct ChannelListView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let categoryID: String
    /// Filters the list in Edit mode (elsewhere the toolbar search searches everything).
    let query: String
    /// Edit mode: hidden channels are listed too, dimmed, every row has a show/hide toggle.
    var editing = false

    /// Switches Live TV to the guide ("Im Programm zeigen").
    var showInGuide: (() -> Void)? = nil
    /// Selects "All" (from the empty favourites view).
    var showAll: (() -> Void)? = nil

    @State private var selection: Int?
    /// The channel whose "Senderinfo" sheet is open.
    @State private var infoChannel: LiveChannel?
    @State private var width: CGFloat = 1000

    /// The detail pane sits right of the list when there is room, below it otherwise.
    private var paneBeside: Bool { width >= 720 }

    var body: some View {
        let channels = app.filteredChannels(categoryID: categoryID, query: query, includeHidden: editing)
        HStack(spacing: 0) {
            list(channels)
            if paneBeside {
                Divider()
                Group {
                    if let id = selection, let channel = app.channel(id) {
                        ChannelDetailPane(channel: channel, number: channels.firstIndex { $0.id == id }.map { $0 + 1 },
                                          onInfo: { infoChannel = channel }, showInGuide: showInGuide)
                    } else {
                        Text("No Channel Selected")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 316)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background {
            // ⌘I and ⌘D for the selected channel (the context menu only shows the shortcuts).
            Group {
                Button("Channel Info…") { infoChannel = selection.flatMap(app.channel) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Favorite") { if let id = selection { app.toggleFavorite("live:\(id)") } }
                    .keyboardShortcut("d", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .sheet(item: $infoChannel) { ChannelInfoView(channel: $0) }
        .onChange(of: app.visibility) { _, _ in dropHiddenSelection() }
        .onChange(of: editing) { _, _ in dropHiddenSelection() }
        .navigationTitle("Live TV")
        .navigationSubtitle("\(channels.count) channels")
        #if DEBUG
        .task {
            // Screenshot runs: IPTV_SELECT=<channel id> shows that channel's programme panel.
            if let id = ProcessInfo.processInfo.environment["IPTV_SELECT"].flatMap(Int.init) {
                selection = id
                // IPTV_TESTSCHEDULE=1: schedules the selected channel's second upcoming show.
                if ProcessInfo.processInfo.environment["IPTV_TESTSCHEDULE"] != nil {
                    while app.channel(id) == nil { try? await Task.sleep(for: .milliseconds(200)) }
                    await app.epg.load(id, client: app.client)
                    let upcoming = (app.epg.guide(id).entries ?? []).filter { $0.start > Date() }
                    if upcoming.count > 1, let channel = app.channel(id) { recorder.schedule(upcoming[1], on: channel).present() }
                }
            }
            // IPTV_TESTINFO=<channel id> opens that channel's "Senderinfo".
            if let id = ProcessInfo.processInfo.environment["IPTV_TESTINFO"].flatMap(Int.init) {
                while app.channel(id) == nil { try? await Task.sleep(for: .milliseconds(200)) }
                infoChannel = app.channel(id)
            }
        }
        #endif
    }

    private func list(_ channels: [LiveChannel]) -> some View {
        List(selection: $selection) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                ChannelRow(channel: channel, isPlaying: isPlaying(channel), editing: editing, number: index + 1)
                    .tag(channel.id)
            }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            if let id = ids.first, let channel = app.channel(id) {
                ChannelMenu(channel: channel, onInfo: { infoChannel = channel }, showInGuide: showInGuide)
            }
        } primaryAction: { ids in
            if let id = ids.first, let channel = app.channel(id) { app.play(channel) }
        }
        .safeAreaInset(edge: .bottom) {
            if !paneBeside, let id = selection, let channel = app.channel(id) {
                EPGPanel(channel: channel, epg: app.epg)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 6) {
                if let error = app.refreshError, !app.channels.isEmpty { ProviderUnreachableBanner(error: error) }
                if editing {
                    Text("Hidden channels do not appear in the list, the guide, search or when switching channels in the player.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, app.refreshError != nil && !app.channels.isEmpty || editing ? 6 : 0)
        }
        .overlay {
            if app.channels.isEmpty && app.isLoading {
                LoadingRows()
            } else if channels.isEmpty && !app.channels.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if channels.isEmpty && categoryID == favoriteChannelsID {
                ContentUnavailableView {
                    Label("No Favorites Yet", systemImage: "star")
                } description: {
                    Text("Mark channels with the star, by right-clicking or with ⌘D. They then appear here.")
                } actions: {
                    if let showAll { Button("Show All Channels", action: showAll) }
                }
            }
        }
    }

    /// A channel hidden outside Edit mode leaves the list, and with it the programme panel.
    private func dropHiddenSelection() {
        guard !editing, let id = selection, let channel = app.channel(id), app.isHidden(channel) else { return }
        selection = nil
    }

    private func isPlaying(_ channel: LiveChannel) -> Bool {
        if case .live(let id, _)? = app.nowPlaying?.kind { return id == channel.id }
        return false
    }
}

/// A clock after the name of a channel whose provider keeps an archive (catch-up).
struct ArchiveMark: View {
    let channel: LiveChannel

    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(String(localized: "Archive: \(channel.archiveDays) days"))
            .accessibilityLabel(Text("Archive: \(channel.archiveDays) days"))
    }
}

struct ChannelRow: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    let isPlaying: Bool
    var editing = false
    /// Position in the shown list – the number the zap banner uses.
    var number: Int? = nil

    var body: some View {
        let hidden = editing && app.isHidden(channel)
        let recording = recorder.active(on: channel.id) != nil
        let offline = app.offlineChannels.contains(channel.id)
        HStack(spacing: 12) {
            if editing { visibilityCheckbox(hidden: hidden) }
            if let number {
                Text(verbatim: "\(number)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
            LogoTile(url: channel.icon, name: channel.displayName, width: 52)
                .opacity(offline ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TaggedName(name: channel.parsed, weight: .semibold)
                    if channel.archiveDays > 0 { ArchiveMark(channel: channel) }
                    Spacer(minLength: 4)
                    if isPlaying { StatusBadge(kind: .playing) }
                    if recording { StatusBadge(kind: .recording) }
                    if offline { StatusBadge(kind: .offline) }
                    if hidden { StatusBadge(kind: .hidden) }
                    Button {
                        app.toggleFavorite("live:\(channel.id)")
                    } label: {
                        Image(systemName: app.isFavorite("live:\(channel.id)") ? "star.fill" : "star")
                            .foregroundStyle(app.isFavorite("live:\(channel.id)") ? .yellow : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(app.isFavorite("live:\(channel.id)") ? "Remove from Favorites" : "Add to Favorites")
                }
                NowNextLine(guide: app.epg.guide(channel.id), recording: recording, offline: offline)
            }
        }
        .opacity(hidden ? 0.42 : 1)
        .frame(minHeight: 50)
        .padding(.vertical, 2)
        .task(id: channel.id) { await app.epg.keepFresh(channel.id, client: app.client) }
    }

    @ViewBuilder
    private func visibilityCheckbox(hidden: Bool) -> some View {
        if app.isChannelHidden(channel.id) || !app.isHidden(channel) {
            VisibilityToggle(hidden: hidden) { app.setChannel(channel.id, hidden: !hidden) }
        } else {
            // Hidden through its category: shown again from there.
            VisibilityToggle(hidden: true) {}
                .disabled(true)
                .help("The category is hidden")
        }
    }
}

/// A row's second line: the current show with its progress and, right-aligned, what follows.
private struct NowNextLine: View {
    @ObservedObject var guide: ChannelGuide
    let recording: Bool
    let offline: Bool

    var body: some View {
        // Redrawn every full minute, so current and next show move on without a scroll.
        TimelineView(LiveClock.everyMinute) { context in
            line(now: LiveClock.now(context.date))
        }
    }

    @ViewBuilder
    private func line(now: Date) -> some View {
        let entries = guide.entries ?? []
        let current = entries.first { $0.start <= now && $0.end > now }
        let next = entries.first { $0.start >= (current?.end ?? now) }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Group {
                    if offline {
                        Text("Channel is offline at the provider")
                    } else if let current {
                        Text(verbatim: current.title)
                    } else if guide.entries != nil {
                        Text("No program data")
                    } else {
                        Text(verbatim: " ")
                    }
                }
                .foregroundStyle(current == nil || offline ? .tertiary : .secondary)
                .lineLimit(1)
                Spacer(minLength: 8)
                if let next, !offline {
                    Text("Next \(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .font(.callout)
            ProgressBar(value: current?.progress(at: now) ?? 0, tint: recording ? Theme.record : Color.primary.opacity(0.5))
                .opacity(current == nil || offline ? 0 : 1)
        }
    }
}

/// "Now" for the Live TV rows and the detail pane. In debug builds `IPTV_CLOCKOFFSET=<s>`
/// shifts it (only there), to test a show change without waiting for one.
enum LiveClock {
    #if DEBUG
    private static let offset = ProcessInfo.processInfo.environment["IPTV_CLOCKOFFSET"].flatMap(Double.init) ?? 0
    #else
    private static let offset: Double = 0
    #endif

    static func now(_ date: Date = Date()) -> Date { date.addingTimeInterval(offset) }

    /// Every full minute, counted in seconds rather than by the calendar: `.everyMinute`
    /// stalls in the hour that repeats when daylight saving time ends.
    static var everyMinute: PeriodicTimelineSchedule {
        .periodic(from: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60), by: 60)
    }
}

/// A thin rounded progress bar (3 pt).
struct ProgressBar: View {
    let value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 3

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: height)
    }
}

/// Edit mode's checkbox: checked means listed.
struct VisibilityToggle: View {
    let hidden: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { !hidden }, set: { _ in action() })) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(hidden ? "Unhide" : "Hide")
            .accessibilityLabel(hidden ? "Unhide" : "Hide")
    }
}

/// "Hide" in a channel's context menu, or "Show" for a channel hidden on its own (Edit mode).
struct ChannelVisibilityButton: View {
    @EnvironmentObject private var app: AppModel
    let channel: LiveChannel

    var body: some View {
        if app.isChannelHidden(channel.id) {
            Button("Unhide") { app.setChannel(channel.id, hidden: false) }
        } else if !app.isHidden(channel) {
            Button("Hide") { app.setChannel(channel.id, hidden: true) }
        }
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
                Text(verbatim: channel.displayName).font(.headline).lineLimit(1)
                Spacer()
                if let now = entries.first(where: { $0.start <= Date() && $0.end > Date() }) {
                    RecordButton(channel: channel, entry: now)
                        .controlSize(.small)
                }
                Button("Play", systemImage: "play.fill") { app.play(channel) }
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
                Text("No program information").foregroundStyle(.secondary).font(.callout)
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

/// "Senderinfo": the channel as the provider delivers it, behind the cleaned name.
struct ChannelInfoView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let channel: LiveChannel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                LogoTile(url: channel.icon, name: channel.displayName, width: 64)
                TaggedName(name: channel.parsed, font: .title3, weight: .semibold)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Name at the provider", channel.name)
                row("Number", "\(channel.id)")
                row("Category at the provider", app.liveCategories.first { $0.id == channel.categoryId }?.name ?? "–")
                row("EPG ID", channel.epgId ?? "–")
                row("Archive", channel.archiveDays > 0 ? String(localized: "\(channel.archiveDays) days") : String(localized: "not available"))
            }
            HStack {
                Button("Copy Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(channel.name, forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled).lineLimit(2)
        }
    }
}

/// The catalog refresh failed while the cached list is shown.
private struct ProviderUnreachableBanner: View {
    @EnvironmentObject private var app: AppModel
    let error: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Provider Not Reachable").font(.callout.weight(.semibold))
                Group {
                    if let updated = app.lastUpdated {
                        Text("You are seeing the channel list from \(updated.formatted(date: .abbreviated, time: .shortened)).")
                    } else {
                        Text(verbatim: error)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Try Again") { Task { await app.loadCatalog(forceRefresh: true) } }
                .disabled(app.isLoading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.warning.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Placeholder rows in the shape of the real ones while the catalog loads for the first time.
private struct LoadingRows: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<12, id: \.self) { i in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 7).fill(.quaternary).frame(width: 52, height: 32)
                        VStack(alignment: .leading, spacing: 7) {
                            Capsule().fill(.quaternary).frame(width: CGFloat(120 + (i * 37) % 90), height: 10)
                            Capsule().fill(.quaternary.opacity(0.7)).frame(width: CGFloat(180 + (i * 23) % 120), height: 8)
                        }
                        Spacer()
                    }
                    .padding(.leading, 54)
                    .frame(height: 58)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text("Loading Channel List").font(.headline)
                Text("Program data follows afterwards").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 12, y: 6)
        }
    }
}
