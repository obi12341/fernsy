import FernsyCore
import FernsyPlayer
import SwiftUI

/// Live TV (design screens `live` and `guide`, tvos-live-and-guide): a switch between the
/// channel list and the guide, both over the one source chosen in the category column.
struct ChannelListScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var showAllCategories = false
    /// The guide's category column is open over the grid: the switch above waits.
    @State private var columnOpen = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ViewSwitch()
                    .padding(.leading, 80)
                    .padding(.bottom, 14)
                    .disabled(columnOpen)
                switch model.liveView {
                case .list: ChannelListView(showAll: $showAllCategories)
                case .guide: GuideScreen(columnOpen: $columnOpen, showAll: $showAllCategories)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TVTheme.background)
            .foregroundStyle(TVTheme.text)
            .navigationDestination(isPresented: $showAllCategories) {
                AllCategoriesScreen { category in
                    model.chooseLiveSource(.category(category.id))
                    showAllCategories = false
                }
            }
        }
    }
}

/// "List | Guide" above Live TV, a focus section between the tab bar and the content.
private struct ViewSwitch: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        HStack(spacing: 12) {
            pill("List", .list, id: "live.view.list")
            pill("Guide", .guide, id: "live.view.guide")
        }
        // As wide as the screen: Down from the tab bar and Up from the first row reach it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func pill(_ title: LocalizedStringKey, _ view: TVModel.LiveView, id: String) -> some View {
        Button { model.liveView = view } label: {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 30)
                .frame(height: 52)
        }
        .buttonStyle(ChipStyle(selected: model.liveView == view))
        .accessibilityIdentifier(id)
        .accessibilityValue(model.liveView == view ? "selected" : "")
    }
}

/// The list view: the category column, the source's channel rows and a pane for the focused
/// channel with now and next.
private struct ChannelListView: View {
    @EnvironmentObject private var model: TVModel
    @Binding var showAll: Bool
    @FocusState private var focusedChannel: Int?
    @FocusState private var focusedEntry: TVModel.LiveSource?

    var body: some View {
        let source = model.liveSource
        let list = model.channels(for: source)
        HStack(alignment: .top, spacing: 40) {
            CategoryColumn(focus: $focusedEntry, choose: { model.chooseLiveSource($0) }, showAll: { showAll = true })
                .frame(width: 330)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, channel in
                        ChannelRowButton(channel: channel, number: index + 1, source: source, guide: model.guide.guide(channel.id))
                            .focused($focusedChannel, equals: channel.id)
                    }
                    if list.isEmpty { EmptySource(source: source) }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            .frame(width: 820)
            // Down to the screen's edge: the rows scroll under the bottom safe area.
            .ignoresSafeArea(edges: .bottom)
            .focusSection()
            ChannelPane(channel: list.first { $0.id == focusedChannel } ?? list.first)
                .frame(width: 540)
                .padding(.top, 12)
                // The preview starts once focus rests on a row for a second (design E).
                .task(id: focusedChannel) {
                    guard let id = focusedChannel, let channel = list.first(where: { $0.id == id }) else { return }
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { model.startPreview(channel) }
                }
        }
        .padding(.leading, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear { model.stopPreview() }
    }
}

// MARK: Category column

/// The source entries of Live TV, in the list and in the guide's open column. An entry becomes
/// the source when clicked, not when focus passes it (tvos-live-and-guide design C).
struct CategoryColumn: View {
    @EnvironmentObject private var model: TVModel
    var focus: FocusState<TVModel.LiveSource?>.Binding
    let choose: (TVModel.LiveSource) -> Void
    let showAll: () -> Void

    var body: some View {
        let selected = model.liveSource
        VStack(alignment: .leading, spacing: 4) {
            entry("Favorites", .favorites, selected: selected)
            entry("Recently Watched", .recent, selected: selected)
            entry("All Channels", .all, selected: selected)
            let pinned = model.pinnedCategories
            // A category chosen in All Categories and not pinned: shown, so the source has a name.
            if case .category(let id) = selected, !pinned.contains(where: { $0.id == id }),
               let category = model.visibleCategories.first(where: { $0.id == id }) {
                entry(LocalizedStringKey(category.displayName), selected, tag: category.parsed.country, selected: selected)
                    .padding(.top, 18)
            }
            if !pinned.isEmpty {
                Text("PINNED")
                    .font(.system(size: 18, weight: .bold)).tracking(1.3)
                    .foregroundStyle(TVTheme.text.opacity(0.45))
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)
                ForEach(pinned) { category in
                    entry(LocalizedStringKey(category.displayName), .category(category.id), tag: category.parsed.country, selected: selected)
                }
            }
            Button { showAll() } label: {
                CategoryLabel(title: "All Categories", count: "\(model.visibleCategories.count) ›", selected: true)
            }
            .buttonStyle(CategoryButtonStyle(outlined: true))
            .padding(.top, 30)
            .accessibilityIdentifier("live.allCategories")
        }
        .focusSection()
    }

    private func entry(_ title: LocalizedStringKey, _ source: TVModel.LiveSource, tag: String? = nil,
                       selected: TVModel.LiveSource) -> some View {
        Button { choose(source) } label: {
            CategoryLabel(title: title, tag: tag, count: "\(model.channels(for: source).count)", selected: selected == source)
        }
        .buttonStyle(CategoryButtonStyle(selected: selected == source))
        .focused(focus, equals: source)
        .accessibilityIdentifier(Self.identifier(source))
        .accessibilityValue(selected == source ? "selected" : "")
    }

    static func identifier(_ source: TVModel.LiveSource) -> String {
        switch source {
        case .favorites: "live.favorites"
        case .recent: "live.recent"
        case .all: "live.all"
        case .category(let id): "live.category.\(id)"
        }
    }
}

private struct CategoryLabel: View {
    let title: LocalizedStringKey
    var tag: String?
    let count: String
    var selected = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title).lineLimit(1).fontWeight(selected ? .semibold : .regular)
            if let tag { CountryTag(text: tag) }
            Spacer(minLength: 8)
            Text(verbatim: count).font(.system(size: 20)).opacity(0.45)
        }
        .font(.system(size: 24))
        .padding(.horizontal, 20)
        .frame(height: 58)
    }
}

/// A category entry: highlighted while selected, light while focused.
private struct CategoryButtonStyle: ButtonStyle {
    var selected = false
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        Entry(configuration: configuration, selected: selected, outlined: outlined)
    }

    private struct Entry: View {
        let configuration: Configuration
        let selected: Bool
        let outlined: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? TVTheme.focusedText : selected || outlined ? TVTheme.text : TVTheme.text.opacity(0.72))
                .background(focused ? TVTheme.focused : selected ? Color.white.opacity(0.14) : outlined ? Color.white.opacity(0.08) : .clear,
                            in: .rect(cornerRadius: 14))
                .overlay { if outlined && !focused { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)) } }
                .scaleEffect(focused ? 1.04 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// The small framed country tag ("DE") of the design.
struct CountryTag: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 15, weight: .bold))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.28), lineWidth: 1.5))
            .opacity(0.75)
    }
}

private struct EmptySource: View {
    let source: TVModel.LiveSource

    var body: some View {
        Text(source == .favorites ? "No favorites yet. Hold a channel’s button and choose “Favorite”."
             : source == .recent ? "Channels you watch appear here." : "No channels.")
            .font(.system(size: 24))
            .foregroundStyle(TVTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(30)
    }
}

// MARK: Channel rows

private struct ChannelRowButton: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    let number: Int
    let source: TVModel.LiveSource
    /// Observed, so the row shows the show once the guide arrives.
    @ObservedObject var guide: ChannelGuide

    var body: some View {
        Button {
            model.zapSource = source
            model.play(channel)
        } label: {
            ChannelRowLabel(channel: channel, number: number, show: model.currentShow(on: channel),
                            favorite: model.isFavorite(channel), recording: model.activeRecording(on: channel) != nil)
        }
        .buttonStyle(ChannelRowStyle())
        .contextMenu { ChannelActions(channel: channel) }
        .onPlayPauseCommand { model.togglePreviewSound() }
        .accessibilityIdentifier("channel.\(channel.id)")
        .task { await model.loadGuide(for: channel) }
    }
}

/// The long-press menu of a channel: record (or stop), favourite, hide.
struct ChannelActions: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel

    var body: some View {
        if let recording = model.activeRecording(on: channel) {
            Button("Stop Recording", systemImage: "stop.circle") { model.recorder.stop(recording.id) }
        } else {
            Button("Record", systemImage: "record.circle") { model.notice = model.recordNow(channel) }
        }
        Button(model.isFavorite(channel) ? "Remove Favorite" : "Favorite", systemImage: model.isFavorite(channel) ? "star.slash" : "star") {
            model.toggleFavorite(channel)
        }
        Button("Hide", systemImage: "eye.slash") { model.setHidden(channel, true) }
    }
}

private struct ChannelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct ChannelRowLabel: View {
    let channel: LiveChannel
    let number: Int
    let show: EPGEntry?
    let favorite: Bool
    let recording: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        HStack(spacing: 22) {
            Text(verbatim: "\(number)")
                .font(.system(size: 20).monospacedDigit()).opacity(0.55)
                .frame(width: 40, alignment: .trailing)
            ChannelLogo(channel: channel)
                .frame(width: 122, height: 75)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(verbatim: channel.displayName).font(.system(size: 27, weight: .semibold)).lineLimit(1)
                    if let tag = channel.parsed.country { CountryTag(text: tag) }
                    if recording { RecordingMark() }
                    if favorite { Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(Color(hex: 0xFFC940)) }
                }
                if let show {
                    HStack(spacing: 14) {
                        Text(verbatim: show.title).opacity(0.72).lineLimit(1).frame(maxWidth: 380, alignment: .leading).fixedSize()
                        ShowProgress(show: show, focused: focused).frame(width: 110, height: 5)
                        Text(minutesLeft(show)).font(.system(size: 21).monospacedDigit()).opacity(0.5)
                    }
                    .font(.system(size: 21))
                } else {
                    Text("No program information").font(.system(size: 21)).opacity(0.45)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(height: 100)
        .foregroundStyle(focused ? TVTheme.focusedText : TVTheme.text)
        .background(focused ? TVTheme.focused : Color.white.opacity(0.06), in: .rect(cornerRadius: 18))
        .scaleEffect(focused ? 1.04 : 1)
        .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 22, y: 22)
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    private func minutesLeft(_ show: EPGEntry) -> String {
        let minutes = max(1, Int((show.end.timeIntervalSinceNow / 60).rounded(.up)))
        return String(localized: "\(minutes) min left")
    }
}

/// The red "REC" mark of a channel that is being recorded.
struct RecordingMark: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: 0xFF4D45)).frame(width: 10, height: 10)
            Text("REC")
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(Color(hex: 0xFF4D45))
    }
}

/// How far a show has run, as the design's thin bar.
struct ShowProgress: View {
    let show: EPGEntry
    var focused = false

    var body: some View {
        let total = show.end.timeIntervalSince(show.start)
        let done = total > 0 ? min(1, max(0, Date().timeIntervalSince(show.start) / total)) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(focused ? Color.black.opacity(0.15) : Color.white.opacity(0.18))
                Capsule().fill(focused ? TVTheme.accent : TVTheme.accentLight).frame(width: geo.size.width * done)
            }
        }
    }
}

/// The channel's logo on the design's dark plate, or its initials while there is none.
struct ChannelLogo: View {
    let channel: LiveChannel
    var plate: Color = Color(hex: 0x2C2B33)
    var radius: CGFloat = 12
    var logoPadding: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(plate)
            if let icon = channel.icon, let url = URL(string: icon) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit().padding(logoPadding)
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
    }

    private var initials: some View {
        let words = channel.displayName.split(separator: " ")
        let text = words.count > 1 ? words.prefix(3).compactMap(\.first).map(String.init).joined() : String(channel.displayName.prefix(4))
        return Text(verbatim: text.uppercased())
            .font(.system(size: 26, weight: .heavy))
            .foregroundStyle(TVTheme.text)
            .minimumScaleFactor(0.5)
            .padding(8)
    }
}

// MARK: Pane

/// A spinner over the preview while its channel loads or buffers (tvos-player-status design 7).
private struct PreviewSpinner: View {
    @ObservedObject var engine: PlayerEngine

    var body: some View {
        let waiting = engine.status == .loading || engine.status == .buffering
        ZStack {
            if waiting { ProgressView().tint(.white) }
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("live.preview.status")
                .accessibilityValue(waiting ? "loading" : "none")
        }
        .allowsHitTesting(false)
    }
}

private struct ChannelPane: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let channel {
                PaneContent(channel: channel, guide: model.guide.guide(channel.id))
            }
        }
    }
}

private struct PaneContent: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    @ObservedObject var guide: ChannelGuide

    var body: some View {
        Group {
            if model.previewing?.id == channel.id {
                // The identifier on the video only: on the whole it would replace the spinner's.
                TVVideoSurface(engine: model.engine)
                    .accessibilityIdentifier("live.preview")
                    .overlay { PreviewSpinner(engine: model.engine) }
                    .overlay(alignment: .topLeading) { LiveBadge().padding(16) }
            } else {
                ChannelLogo(channel: channel, radius: 20, logoPadding: 70)
            }
        }
        .frame(width: 540, height: 304)
        .clipShape(.rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1)) }
        if let show = model.currentShow(on: channel) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOW · \(Self.span(show))")
                    .font(.system(size: 19, weight: .bold)).tracking(1.3)
                    .foregroundStyle(TVTheme.tertiary)
                Text(verbatim: show.title).font(.system(size: 34, weight: .bold)).lineLimit(2)
                if !show.description.isEmpty {
                    Text(verbatim: show.description)
                        .font(.system(size: 22)).lineSpacing(6).lineLimit(4)
                        .foregroundStyle(TVTheme.secondary)
                }
            }
        }
        let next = model.nextShows(on: channel)
        if !next.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("NEXT").font(.system(size: 19, weight: .bold)).tracking(1.3).foregroundStyle(TVTheme.tertiary)
                ForEach(next, id: \.start) { show in
                    HStack(spacing: 16) {
                        Text(show.start, format: .dateTime.hour().minute())
                            .monospacedDigit().foregroundStyle(TVTheme.text.opacity(0.55))
                        Text(verbatim: show.title).lineLimit(1)
                    }
                }
            }
            .font(.system(size: 22))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
        }
    }

    static func span(_ show: EPGEntry) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(show.start.formatted(style))–\(show.end.formatted(style))"
    }
}

/// The red "LIVE" badge on a live picture.
struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(.system(size: 16, weight: .heavy)).tracking(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(TVTheme.live, in: .capsule)
            .foregroundStyle(.white)
    }
}
