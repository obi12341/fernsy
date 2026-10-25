import SwiftUI

/// Live TV in the player: the channels of a category over the picture, with what is on now,
/// to switch without leaving the player (L). The screen owns the state (open, category,
/// highlight) because the keyboard drives it from there.
struct PlayerChannelList: View {
    @EnvironmentObject private var app: AppModel
    /// The category shown: the zapped one at first, the menu changes it.
    @Binding var categoryID: String
    /// The row the keyboard is on (a channel id).
    let highlighted: Int?
    let playingID: Int?
    let onTune: (LiveChannel) -> Void
    /// Hover, scrolling and clicks keep the list open.
    let onActivity: () -> Void

    /// The channels listed for `categoryID`: favourites and recently watched as in the library,
    /// a category in zap order; hidden channels left out.
    static func channels(_ categoryID: String, app: AppModel) -> [LiveChannel] {
        switch categoryID {
        case favoriteChannelsID, recentChannelsID: app.filteredChannels(categoryID: categoryID, query: "")
        default: app.zapList(categoryId: categoryID)
        }
    }

    var body: some View {
        let channels = Self.channels(categoryID, app: app)
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                        PlayerChannelRow(channel: channel, number: index + 1, isPlaying: channel.id == playingID)
                            .id(channel.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onTune(channel) }
                            .listRowBackground(rowBackground(channel))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear { proxy.scrollTo(highlighted ?? playingID, anchor: .center) }
                .onChange(of: highlighted) { _, id in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
                .onChange(of: categoryID) { _, _ in proxy.scrollTo(highlighted ?? playingID, anchor: .center) }
            }
            if channels.isEmpty {
                Text("Keine Sender").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .onContinuousHover { _ in onActivity() }
        .simultaneousGesture(TapGesture().onEnded { onActivity() })
    }

    private var header: some View {
        HStack {
            Menu {
                Button("Favoriten") { categoryID = favoriteChannelsID }
                Button("Zuletzt gesehen") { categoryID = recentChannelsID }
                Divider()
                ForEach(app.visibleCategories(app.liveCategories).filter { !app.isCategoryHidden($0.id) }) { category in
                    Button(category.displayName) { categoryID = category.id }
                }
            } label: {
                Text(verbatim: title).font(.headline)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Text(verbatim: "L").font(.caption.monospaced()).foregroundStyle(.tertiary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary, lineWidth: 0.5))
                .help("Senderliste schließen (L, Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var title: String {
        switch categoryID {
        case favoriteChannelsID: String(localized: "Favoriten")
        case recentChannelsID: String(localized: "Zuletzt gesehen")
        case allCategoryID: String(localized: "Alle")
        default: app.liveCategories.first { $0.id == categoryID }?.displayName ?? String(localized: "Alle")
        }
    }

    @ViewBuilder
    private func rowBackground(_ channel: LiveChannel) -> some View {
        if channel.id == highlighted {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(channel.id == playingID ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
                .padding(.horizontal, 6)
        } else if channel.id == playingID {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.22)).padding(.horizontal, 6)
        } else {
            Color.clear
        }
    }
}

/// A channel in the player's list: narrower than the library row, without the next show.
private struct PlayerChannelRow: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    let number: Int
    let isPlaying: Bool

    var body: some View {
        let recording = recorder.active(on: channel.id) != nil
        let offline = app.offlineChannels.contains(channel.id)
        HStack(spacing: 10) {
            Group {
                if isPlaying {
                    Image(systemName: "play.fill").font(.caption2).foregroundStyle(Color.accentColor)
                } else {
                    Text(verbatim: "\(number)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            .frame(width: 24, alignment: .trailing)
            LogoTile(url: channel.icon, name: channel.displayName, width: 40)
                .opacity(offline ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TaggedName(name: channel.parsed, font: .callout, weight: .semibold)
                    Spacer(minLength: 4)
                    if recording { StatusBadge(kind: .recording) }
                    if offline { StatusBadge(kind: .offline) }
                }
                PlayerNowLine(guide: app.epg.guide(channel.id), recording: recording, offline: offline)
            }
        }
        .padding(.vertical, 3)
        .task(id: channel.id) { await app.epg.keepFresh(channel.id, client: app.client) }
    }
}

/// The show on now with its progress, moving on with the minute clock.
private struct PlayerNowLine: View {
    @ObservedObject var guide: ChannelGuide
    let recording: Bool
    let offline: Bool

    var body: some View {
        TimelineView(LiveClock.everyMinute) { context in
            let now = LiveClock.now(context.date)
            let current = (guide.entries ?? []).first { $0.start <= now && $0.end > now }
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if offline {
                        Text("Sender ist beim Anbieter offline")
                    } else if let current {
                        Text(verbatim: current.title)
                    } else if guide.entries != nil {
                        Text("Keine Programmdaten")
                    } else {
                        Text(verbatim: " ")
                    }
                }
                .font(.caption)
                .foregroundStyle(current == nil || offline ? .tertiary : .secondary)
                .lineLimit(1)
                ProgressBar(value: current?.progress(at: now) ?? 0, tint: recording ? Theme.record : Color.primary.opacity(0.5))
                    .opacity(current == nil || offline ? 0 : 1)
            }
        }
    }
}
