import FernsyCore
import FernsyPlayer
import SwiftUI

/// Live TV (ios-app "Live TV"): Liste and Programm over one source, chosen in the toolbar menu.
struct LiveTVView: View {
    @EnvironmentObject private var model: TVModel
    @State private var showAllCategories = false

    var body: some View {
        Group {
            switch model.liveView {
            case .list: ChannelListView()
            case .guide: GuideView()
            }
        }
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle(sourceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.liveView) {
                    Text("List").tag(TVModel.LiveView.list)
                    Text("Guide").tag(TVModel.LiveView.guide)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityIdentifier("live.view")
            }
            ToolbarItem(placement: .topBarLeading) {
                SourceMenu(showAll: { showAllCategories = true })
            }
        }
        #if DEBUG
        // IPTV_ALLCATEGORIES=1: opens All Categories (screenshots without touch input).
        .onAppear { if ProcessInfo.processInfo.environment["IPTV_ALLCATEGORIES"] == "1" { showAllCategories = true } }
        #endif
        .navigationDestination(isPresented: $showAllCategories) {
            AllCategoriesView { category in
                model.chooseLiveSource(.category(category.id))
                showAllCategories = false
            }
        }
    }

    private var sourceTitle: String {
        switch model.liveSource {
        case .favorites: String(localized: "Favorites")
        case .recent: String(localized: "Recently Watched")
        case .all: String(localized: "All Channels")
        case .category(let id): model.categories.first { $0.id == id }?.displayName ?? String(localized: "Live TV")
        }
    }
}

/// The sources of Live TV: Favorites, Recently Watched, All Channels, the pinned categories and
/// All Categories (the Apple TV's category column as a menu).
private struct SourceMenu: View {
    @EnvironmentObject private var model: TVModel
    let showAll: () -> Void

    var body: some View {
        let selected = model.liveSource
        Menu {
            Picker("Source", selection: Binding(get: { selected }, set: { model.chooseLiveSource($0) })) {
                entry("Favorites", .favorites)
                entry("Recently Watched", .recent)
                entry("All Channels", .all)
                if case .category(let id) = selected, !model.pinnedCategories.contains(where: { $0.id == id }),
                   let category = model.visibleCategories.first(where: { $0.id == id }) {
                    entry(LocalizedStringKey(category.displayName), selected)
                }
            }
            if !model.pinnedCategories.isEmpty {
                Section("Pinned") {
                    Picker("Pinned", selection: Binding(get: { selected }, set: { model.chooseLiveSource($0) })) {
                        ForEach(model.pinnedCategories) { category in
                            entry(LocalizedStringKey(category.displayName), .category(category.id))
                        }
                    }
                }
            }
            Button("All Categories", systemImage: "square.grid.2x2") { showAll() }
                .accessibilityIdentifier("live.allCategories")
        } label: {
            Label("Categories", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("live.sources")
    }

    private func entry(_ title: LocalizedStringKey, _ source: TVModel.LiveSource) -> some View {
        Text(title).badge(model.channels(for: source).count).tag(source)
    }
}

/// The source's channels as rows; on a wide iPad with the pane of the selected channel.
private struct ChannelListView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var paneChannel: Int?

    var body: some View {
        let source = model.liveSource
        let list = model.channels(for: source)
        GeometryReader { geo in
            let withPane = sizeClass == .regular && geo.size.width > 900
            HStack(spacing: 0) {
                List {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, channel in
                        ChannelRow(channel: channel, number: index + 1, source: source, guide: model.guide.guide(channel.id),
                                   onInfo: withPane ? { paneChannel = channel.id } : nil)
                            .listRowBackground(paneChannel == channel.id && withPane ? Color.white.opacity(0.1) : Color.clear)
                    }
                    if list.isEmpty { EmptySource(source: source).listRowBackground(Color.clear) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                if withPane, let channel = list.first(where: { $0.id == paneChannel }) ?? list.first {
                    ChannelPane(channel: channel, guide: model.guide.guide(channel.id))
                        .frame(width: min(440, geo.size.width * 0.38))
                        .padding(20)
                }
            }
        }
    }
}

private struct EmptySource: View {
    let source: TVModel.LiveSource

    var body: some View {
        Text(source == .favorites ? "No favorites yet. Touch and hold a channel and choose “Favorite”."
             : source == .recent ? "Channels you watch appear here." : "No channels.")
            .foregroundStyle(TVTheme.secondary)
            .padding(.vertical, 30)
    }
}

/// A channel row: number, logo, name with tags and star, the show on now with progress and
/// time left, and what follows. Tapping plays it; touch and hold offers favourite and hide.
struct ChannelRow: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    let number: Int
    let source: TVModel.LiveSource
    /// Observed, so the row shows the show once the guide arrives.
    @ObservedObject var guide: ChannelGuide
    var onInfo: (() -> Void)?

    var body: some View {
        Button {
            model.zapSource = source
            Task { await model.zap(to: channel) }
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: "\(number)")
                    .font(.caption.monospacedDigit()).foregroundStyle(TVTheme.tertiary)
                    .frame(width: 28, alignment: .trailing)
                ChannelLogo(channel: channel)
                    .frame(width: 64, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(verbatim: channel.displayName).font(.headline).lineLimit(1)
                        if let tag = channel.parsed.country { CountryTag(text: tag) }
                        if channel.archiveDays > 0 { ArchiveMark(channel: channel) }
                        if model.isFavorite(channel) {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(TVTheme.favorite)
                        }
                    }
                    if let show = model.currentShow(on: channel) {
                        HStack(spacing: 8) {
                            Text(verbatim: show.title).lineLimit(1)
                            Spacer(minLength: 4)
                            ShowProgress(show: show).frame(width: 44, height: 4)
                            Text(minutesLeft(show)).monospacedDigit().foregroundStyle(TVTheme.tertiary)
                        }
                        .font(.subheadline)
                        .foregroundStyle(TVTheme.secondary)
                        if let next = model.nextShows(on: channel, count: 1).first {
                            HStack(spacing: 6) {
                                Text(next.start, format: .dateTime.hour().minute()).monospacedDigit()
                                Text(verbatim: next.title).lineLimit(1)
                            }
                            .font(.caption)
                            .foregroundStyle(TVTheme.tertiary)
                        }
                    } else {
                        Text("No program information").font(.subheadline).foregroundStyle(TVTheme.tertiary)
                    }
                }
                if let onInfo {
                    Button(action: onInfo) { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(TVTheme.accentLight)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu { ChannelActions(channel: channel) }
        .accessibilityIdentifier("channel.\(channel.id)")
        .task { await model.loadGuide(for: channel) }
    }

    private func minutesLeft(_ show: EPGEntry) -> String {
        let minutes = max(1, Int((show.end.timeIntervalSinceNow / 60).rounded(.up)))
        return String(localized: "\(minutes) min left")
    }
}

/// The context menu of a channel: favourite and hide (no recording on iPhone and iPad).
struct ChannelActions: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel

    var body: some View {
        Button(model.isFavorite(channel) ? "Remove Favorite" : "Favorite", systemImage: model.isFavorite(channel) ? "star.slash" : "star") {
            model.toggleFavorite(channel)
        }
        Button("Hide", systemImage: "eye.slash", role: .destructive) { model.setHidden(channel, true) }
    }
}

/// The pane beside the list on a wide iPad: logo, now with its description, and next.
private struct ChannelPane: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    @ObservedObject var guide: ChannelGuide

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    model.zapSource = model.liveSource
                    Task { await model.zap(to: channel) }
                } label: {
                    ChannelLogo(channel: channel, radius: 16, logoPadding: 40)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "play.circle.fill").font(.largeTitle).padding(12).foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)
                Text(verbatim: channel.displayName).font(.title3.bold())
                if let show = model.currentShow(on: channel) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOW · \(Self.span(show))").font(.caption.weight(.bold)).foregroundStyle(TVTheme.tertiary)
                        Text(verbatim: show.title).font(.title2.bold())
                        if !show.description.isEmpty {
                            Text(verbatim: show.description).foregroundStyle(TVTheme.secondary).lineLimit(6)
                        }
                    }
                }
                let next = model.nextShows(on: channel, count: 3)
                if !next.isEmpty {
                    Divider()
                    Text("NEXT").font(.caption.weight(.bold)).foregroundStyle(TVTheme.tertiary)
                    ForEach(next, id: \.start) { show in
                        HStack(spacing: 12) {
                            Text(show.start, format: .dateTime.hour().minute()).monospacedDigit().foregroundStyle(TVTheme.tertiary)
                            Text(verbatim: show.title).lineLimit(1)
                        }
                    }
                }
            }
        }
        .task(id: channel.id) { await model.loadGuide(for: channel) }
    }

    static func span(_ show: EPGEntry) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(show.start.formatted(style))–\(show.end.formatted(style))"
    }
}

// MARK: Small parts

/// The small framed country tag ("DE").
struct CountryTag: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 4)
            .frame(height: 15)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.28), lineWidth: 1))
            .opacity(0.75)
    }
}

/// A clock after the name of a channel whose provider keeps an archive (catch-up).
struct ArchiveMark: View {
    let channel: LiveChannel

    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.caption.weight(.semibold))
            .foregroundStyle(TVTheme.tertiary)
            .accessibilityLabel(Text("Archive: \(channel.archiveDays) days"))
    }
}

/// How far a show has run, as a thin bar.
struct ShowProgress: View {
    let show: EPGEntry

    var body: some View {
        let total = show.end.timeIntervalSince(show.start)
        let done = total > 0 ? min(1, max(0, Date().timeIntervalSince(show.start) / total)) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(TVTheme.accentLight).frame(width: geo.size.width * done)
            }
        }
    }
}

/// The channel's logo on a dark plate, or its initials while there is none.
struct ChannelLogo: View {
    let channel: LiveChannel
    var plate: Color = Color(hex: 0x2C2B33)
    var radius: CGFloat = 8
    var logoPadding: CGFloat = 5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(plate)
            if let icon = channel.icon, let url = URL(string: icon) {
                RemoteImage(url: url, maxPixel: 300) { initials }
                    .scaledToFit()
                    .padding(logoPadding)
            } else {
                initials
            }
        }
        .clipShape(.rect(cornerRadius: radius))
    }

    private var initials: some View {
        let words = channel.displayName.split(separator: " ")
        let text = words.count > 1 ? words.prefix(3).compactMap(\.first).map(String.init).joined() : String(channel.displayName.prefix(4))
        return Text(verbatim: text.uppercased())
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(TVTheme.text)
            .minimumScaleFactor(0.5)
            .padding(4)
    }
}

// MARK: All categories

/// Every live category with its country tag and channel count, chips per country, a search
/// field; tap opens it in Live TV, touch and hold pins, unpins or hides it.
struct AllCategoriesView: View {
    @EnvironmentObject private var model: TVModel
    let open: (XCategory) -> Void
    @State private var filter: Filter = .all
    @State private var query = ""

    enum Filter: Hashable { case all, pinned, country(String), none }

    var body: some View {
        let categories = model.visibleCategories
        let countries = Array(Set(categories.compactMap(\.parsed.country))).sorted()
        let shown = categories.filter { category in
            switch filter {
            case .all: true
            case .pinned: model.isPinned(category)
            case .country(let code): category.parsed.country == code
            case .none: category.parsed.country == nil
            }
        }.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All", .all, count: categories.count)
                        chip("Pinned", .pinned, count: categories.filter(model.isPinned).count)
                        ForEach(countries, id: \.self) { code in
                            chip(LocalizedStringKey(code), .country(code), count: categories.filter { $0.parsed.country == code }.count)
                        }
                        chip("No Country", .none, count: categories.filter { $0.parsed.country == nil }.count)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                ForEach(shown) { category in
                    Button { open(category) } label: {
                        HStack {
                            Text(verbatim: category.displayName)
                            if let tag = category.parsed.country { CountryTag(text: tag) }
                            if model.isPinned(category) { Image(systemName: "pin.fill").font(.caption).foregroundStyle(TVTheme.accentLight) }
                            Spacer()
                            Text(verbatim: "\(model.channels(in: category).count)").foregroundStyle(TVTheme.tertiary).monospacedDigit()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(model.isPinned(category) ? "Unpin" : "Pin", systemImage: model.isPinned(category) ? "pin.slash" : "pin") {
                            model.setPinned(category, !model.isPinned(category))
                        }
                        Button("Hide", systemImage: "eye.slash", role: .destructive) { model.setHidden(category, true) }
                    }
                    .accessibilityIdentifier("category.\(category.id)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .searchable(text: $query, prompt: Text("Search Categories"))
        .navigationTitle("All Categories")
    }

    private func chip(_ title: LocalizedStringKey, _ value: Filter, count: Int) -> some View {
        Button { filter = value } label: {
            HStack(spacing: 4) {
                Text(title)
                Text(verbatim: "\(count)").opacity(0.6)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(filter == value ? TVTheme.focused : Color.white.opacity(0.1), in: .capsule)
            .foregroundStyle(filter == value ? TVTheme.focusedText : TVTheme.text)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("categories.chip.\(title)")
    }
}
