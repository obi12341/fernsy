import FernsyCore
import FernsyPlayer
import SwiftUI

/// Programme grid: one row per channel, time runs horizontally. The channel column and
/// the time ruler stay in place while the grid scrolls underneath.
///
/// Scrolling must not invalidate the view tree: the sticky parts follow the scroll offset
/// through `visualEffect` (applied at render time), and the only scroll-derived state
/// (`GuideScroll`) is read by the small ruler label alone.
struct GuideView: View {
    @EnvironmentObject private var app: AppModel
    let categoryID: String
    /// The category column is hidden while the guide shows; the toolbar menu picks it.
    var categorySelection: Binding<String?>? = nil

    struct Selection: Equatable {
        let channelId: Int
        let entry: EPGEntry
        static func == (a: Self, b: Self) -> Bool { a.channelId == b.channelId && a.entry.id == b.entry.id }
    }

    @State private var origin = GuideLayout.origin(for: Date())
    /// 0 = today (from two hours back), 1…3 = the following days from midnight.
    @State private var dayOffset = 0
    static let maxDays = 3
    @State private var selection: Selection?
    @State private var scroll = GuideScroll()
    @State private var position = ScrollPosition()

    var body: some View {
        let channels = app.filteredChannels(categoryID: categoryID, query: "")
        let playing = playingChannelID
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(channels) { channel in
                            GuideRow(channel: channel, guide: app.epg.guide(channel.id), origin: origin, now: context.date,
                                     scroll: scroll, isPlaying: channel.id == playing, selection: $selection)
                        }
                    } header: {
                        GuideRuler(origin: origin, now: context.date, scroll: scroll)
                    }
                }
                .frame(width: GuideLayout.channelWidth + GuideLayout.timelineWidth, alignment: .leading)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
                scroll.update(rect)
            }
        }
        .onAppear { scrollToNow() }
        #if DEBUG
        // IPTV_GUIDESCROLL=x,y: scroll there after loading (layout checks of the sticky parts).
        // IPTV_GUIDEDAY=<n> and IPTV_GUIDETIME=<hh:mm>: that day and time.
        .task {
            let env = ProcessInfo.processInfo.environment
            if let day = env["IPTV_GUIDEDAY"].flatMap(Int.init) {
                try? await Task.sleep(for: .seconds(3))
                setDay(day)
            }
            // IPTV_GUIDESELECT=<channel id>:<n>: selects that channel's n-th upcoming show.
            if let spec = env["IPTV_GUIDESELECT"]?.split(separator: ":").compactMap({ Int($0) }), spec.count == 2 {
                while app.channel(spec[0]) == nil { try? await Task.sleep(for: .milliseconds(200)) }
                await app.epg.load(spec[0], client: app.client)
                let upcoming = (app.epg.guide(spec[0]).entries ?? []).filter { $0.start > Date() }
                if upcoming.count > spec[1] { selection = Selection(channelId: spec[0], entry: upcoming[spec[1]]) }
            }
            if let time = env["IPTV_GUIDETIME"] {
                try? await Task.sleep(for: .seconds(env["IPTV_GUIDEDAY"] == nil ? 3 : 1))
                jump(to: time)
            }
            let parts = ProcessInfo.processInfo.environment["IPTV_GUIDESCROLL"]?.split(separator: ",").compactMap { Double($0) }
            guard let parts, parts.count == 2 else { return }
            try? await Task.sleep(for: .seconds(4))
            position.scrollTo(point: CGPoint(x: parts[0], y: parts[1]))
        }
        #endif
        .onChange(of: categoryID) { _, _ in selection = nil }
        .onChange(of: app.visibility) { _, _ in
            // A hidden channel leaves the guide, and with it its programme details.
            if let id = selection?.channelId, let channel = app.channel(id), app.isHidden(channel) { selection = nil }
        }
        .safeAreaInset(edge: .bottom) {
            if let selection, let channel = app.channel(selection.channelId) {
                GuideDetail(channel: channel, entry: selection.entry) { self.selection = nil }
            }
        }
        .toolbar {
            if let categorySelection {
                ToolbarItem(placement: .navigation) { categoryMenu(categorySelection) }
            }
            ToolbarItem {
                ControlGroup {
                    Button("Previous Day", systemImage: "chevron.left") { setDay(dayOffset - 1) }
                        .disabled(dayOffset == 0)
                    Menu {
                        ForEach(Self.jumps, id: \.self) { time in
                            Button(time) { jump(to: time) }
                        }
                    } label: {
                        Text(verbatim: dayTitle).monospacedDigit()
                    }
                    .help("Jump to a time")
                    Button("Next Day", systemImage: "chevron.right") { setDay(dayOffset + 1) }
                        .disabled(dayOffset == Self.maxDays)
                }
            }
            ToolbarItem {
                Button { scrollToNow() } label: {
                    Text("Now").fontWeight(.semibold).foregroundStyle(Theme.record)
                }
                .help("Jump to the current time")
            }
        }
        .navigationTitle("Live TV")
        .navigationSubtitle("\(channels.count) channels")
    }

    private func categoryMenu(_ selection: Binding<String?>) -> some View {
        let categories = app.visibleCategories(app.liveCategories).filter { !app.isCategoryHidden($0.id) }
        let current = selection.wrappedValue ?? allCategoryID
        let title: String = switch current {
        case allCategoryID: String(localized: "All Channels")
        case favoriteChannelsID: String(localized: "Favorites")
        case recentChannelsID: String(localized: "Recently Watched")
        default: categories.first { $0.id == current }?.displayName ?? String(localized: "All Channels")
        }
        return Menu {
            Picker("Category", selection: Binding(get: { current }, set: { selection.wrappedValue = $0 })) {
                Text("All Channels").tag(allCategoryID)
                Text("Favorites").tag(favoriteChannelsID)
                Text("Recently Watched").tag(recentChannelsID)
                Divider()
                ForEach(categories) { Text(verbatim: $0.displayName).tag($0.id) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(verbatim: title).fontWeight(.semibold)
        }
        .help("Category of the guide")
    }

    static let jumps = ["06:00", "12:00", "18:00", "20:15", "23:00"]

    private var dayTitle: String {
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let name = dayOffset == 0 ? String(localized: "Today") : dayOffset == 1 ? String(localized: "Tomorrow")
            : day.formatted(.dateTime.weekday(.wide))
        return "\(name), \(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    private func origin(forDay offset: Int) -> Date {
        if offset == 0 { return GuideLayout.origin(for: Date()) }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// Another day, keeping the time of day at the left edge.
    private func setDay(_ offset: Int) {
        let offset = min(max(0, offset), Self.maxDays)
        let left = origin.addingTimeInterval(Double(max(0, scroll.offset.x) / GuideLayout.pointsPerMinute) * 60)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: left)
        dayOffset = offset
        origin = origin(forDay: offset)
        scrollTo(hour: parts.hour ?? 20, minute: parts.minute ?? 0, animated: false)
    }

    /// "20:15": that time on the shown day, a quarter of an hour in from the left edge.
    private func jump(to time: String) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        scrollTo(hour: parts[0], minute: parts[1], animated: true)
    }

    private func scrollTo(hour: Int, minute: Int, animated: Bool) {
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        guard let target = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return }
        let x = max(0, GuideLayout.x(of: target.addingTimeInterval(-15 * 60), origin: origin))
        let point = CGPoint(x: x, y: max(0, scroll.offset.y))
        if animated { withAnimation { position.scrollTo(point: point) } } else {
            // After an origin change the grid lays out first.
            Task { @MainActor in position.scrollTo(point: point) }
        }
    }

    private func scrollToNow() {
        let now = Date()
        if dayOffset != 0 { dayOffset = 0; origin = GuideLayout.origin(for: now) }
        if now.timeIntervalSince(origin) > GuideLayout.span - 4 * 3600 { origin = GuideLayout.origin(for: now) }
        let x = GuideLayout.x(of: now.addingTimeInterval(-30 * 60), origin: origin)
        // Keep the vertical position: scrolling only one axis lets the other jump.
        withAnimation { position.scrollTo(point: CGPoint(x: max(0, x), y: max(0, scroll.offset.y))) }
    }

    private var playingChannelID: Int? {
        if case .live(let id, _)? = app.nowPlaying?.kind { return id }
        return nil
    }
}

/// Scroll state outside the view tree. The observed values change in coarse steps, not
/// per frame: `leftSlot` (ruler day label) per half hour, `chunk` (which programmes the
/// rows build) per two hours.
@Observable
final class GuideScroll {
    @ObservationIgnored var offset: CGPoint = .zero
    var leftSlot = 0
    var chunk = 0
    var visibleChunks = 2

    func update(_ visible: CGRect) {
        offset = visible.origin
        let x = max(0, visible.minX)
        let slot = Int(x / GuideLayout.slotWidth)
        if slot != leftSlot { leftSlot = slot }
        let chunk = Int(x / GuideLayout.chunkWidth)
        if chunk != self.chunk { self.chunk = chunk }
        let count = Int((visible.width / GuideLayout.chunkWidth).rounded(.up)) + 1
        if count != visibleChunks { visibleChunks = count }
    }
}

enum GuideLayout {
    static let channelWidth: CGFloat = 188
    static let rowHeight: CGFloat = 50
    static let rulerHeight: CGFloat = 26
    static let pointsPerMinute: CGFloat = 5
    static let span: TimeInterval = 24 * 3600
    static let slot: TimeInterval = 30 * 60
    static var slotWidth: CGFloat { CGFloat(slot / 60) * pointsPerMinute }
    /// Rows build only the programmes near the visible part, in steps of this length.
    static let chunk: TimeInterval = 2 * 3600
    static var chunkWidth: CGFloat { CGFloat(chunk / 60) * pointsPerMinute }
    static var timelineWidth: CGFloat { CGFloat(span / 60) * pointsPerMinute }

    /// Two hours back, on the half hour, so the recent past is reachable.
    static func origin(for now: Date) -> Date {
        let back = now.addingTimeInterval(-2 * 3600).timeIntervalSince1970
        return Date(timeIntervalSince1970: (back / slot).rounded(.down) * slot)
    }

    /// Horizontal position of `date` on the timeline (without the channel column).
    static func x(of date: Date, origin: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(origin) / 60) * pointsPerMinute
    }
}

private extension View {
    /// Keeps the view at the left edge of the scroll view while the content scrolls
    /// horizontally. Render-time only, no view update per frame.
    func stickyLeading() -> some View {
        visualEffect { content, proxy in
            content.offset(x: -proxy.frame(in: .scrollView).minX)
        }
    }
}

// MARK: - Ruler

private struct GuideRuler: View {
    let origin: Date
    let now: Date
    let scroll: GuideScroll

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(0..<Int(GuideLayout.span / GuideLayout.slot), id: \.self) { index in
                    let time = origin.addingTimeInterval(Double(index) * GuideLayout.slot)
                    HStack(spacing: 6) {
                        Rectangle().fill(.separator).frame(width: 1)
                        Text(label(time)).monospacedDigit()
                            .fontWeight(Calendar.current.component(.minute, from: time) == 0 ? .semibold : .regular)
                    }
                    .frame(width: GuideLayout.slotWidth, alignment: .leading)
                }
            }
            .padding(.leading, GuideLayout.channelWidth)

            NowMarker(x: GuideLayout.channelWidth + GuideLayout.x(of: now, origin: origin))
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Theme.record, in: Capsule())
                .fixedSize()
                .frame(width: 70)
                .padding(.leading, max(0, GuideLayout.channelWidth + GuideLayout.x(of: now, origin: origin) - 35))
                .padding(.top, 4)
                .opacity(now < origin ? 0 : 1)

            DayLabel(origin: origin, scroll: scroll)
                .padding(.leading, 12)
                .frame(width: GuideLayout.channelWidth, height: GuideLayout.rulerHeight, alignment: .leading)
                .background(.bar)
                .background(.background)
                .stickyLeading()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: GuideLayout.channelWidth + GuideLayout.timelineWidth, height: GuideLayout.rulerHeight, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func label(_ time: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        if c.hour == 0 && c.minute == 0 { return time.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
        return time.formatted(date: .omitted, time: .shortened)
    }
}

/// The day at the left edge of the visible timeline.
private struct DayLabel: View {
    let origin: Date
    let scroll: GuideScroll

    var body: some View {
        let time = origin.addingTimeInterval(Double(scroll.leftSlot) * GuideLayout.slot)
        Text(day(time)).fontWeight(.semibold)
    }

    private func day(_ time: Date) -> String {
        if Calendar.current.isDateInToday(time) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(time) { return String(localized: "Tomorrow") }
        if Calendar.current.isDateInYesterday(time) { return String(localized: "Yesterday") }
        return time.formatted(.dateTime.weekday(.wide).day().month())
    }
}

/// The red "now" line. The sticky channel column is drawn above it and covers it.
private struct NowMarker: View {
    let x: CGFloat

    var body: some View {
        // On a later day "now" lies before the timeline: no line.
        Rectangle().fill(Theme.record).frame(width: 2).padding(.leading, max(0, x - 1))
            .opacity(x < GuideLayout.channelWidth ? 0 : 1)
    }
}

// MARK: - Row

private struct GuideRow: View {
    @State private var showsInfo = false
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    @ObservedObject var guide: ChannelGuide
    let origin: Date
    let now: Date
    let scroll: GuideScroll
    let isPlaying: Bool
    @Binding var selection: GuideView.Selection?

    var body: some View {
        let end = origin.addingTimeInterval(GuideLayout.span)
        // One chunk of margin on each side, so cells exist before they scroll into view.
        let from = origin.addingTimeInterval(Double(scroll.chunk - 1) * GuideLayout.chunk)
        let to = origin.addingTimeInterval(Double(scroll.chunk + scroll.visibleChunks + 1) * GuideLayout.chunk)
        ZStack(alignment: .topLeading) {
            if let entries = guideEntries {
                if !entries.contains(where: { $0.end > origin && $0.start < end }) {
                    noData
                } else {
                    ForEach(entries.filter { $0.end > max(origin, from) && $0.start < min(end, to) }) { entry in
                        let x0 = GuideLayout.x(of: max(entry.start, origin), origin: origin)
                        let x1 = GuideLayout.x(of: min(entry.end, end), origin: origin)
                        GuideCell(entry: entry, now: now, width: x1 - x0,
                                  selected: selection == GuideView.Selection(channelId: channel.id, entry: entry),
                                  recording: recorder.recording(channelId: channel.id, entry: entry)?.status)
                            .onTapGesture(count: 2) { app.play(channel) }
                            .onTapGesture { selection = GuideView.Selection(channelId: channel.id, entry: entry) }
                            .contextMenu {
                                Button("Play") { app.play(channel) }
                                RecordButton(channel: channel, entry: entry)
                            }
                            .padding(.leading, GuideLayout.channelWidth + x0)
                    }
                }
            } else {
                placeholder(nil)
            }

            NowMarker(x: GuideLayout.channelWidth + GuideLayout.x(of: now, origin: origin))

            channelCell.stickyLeading()
        }
        .frame(width: GuideLayout.channelWidth + GuideLayout.timelineWidth, height: GuideLayout.rowHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { Divider() }
        .task(id: channel.id) {
            // Rows that only fly past while scrolling fast are not worth a download.
            if guide.entries == nil {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
            }
            await app.epg.load(channel.id, client: app.client)
        }
    }

    private var channelCell: some View {
        HStack(spacing: 8) {
            LogoTile(url: channel.icon, name: channel.displayName, width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: channel.displayName)
                    .font(.callout)
                    .fontWeight(isPlaying ? .semibold : .regular)
                    .lineLimit(1)
                if channel.parsed.country != nil || channel.parsed.quality != nil {
                    HStack(spacing: 4) {
                        if let country = channel.parsed.country { NameTag(text: country) }
                        if let quality = channel.parsed.quality { NameTag(text: quality, prominent: false) }
                    }
                }
            }
            Spacer(minLength: 0)
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint).font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: GuideLayout.channelWidth, height: GuideLayout.rowHeight)
        .background(.background)
        .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.play(channel) }
        .contextMenu {
            Button("Play") { app.play(channel) }
            ChannelVisibilityButton(channel: channel)
            Divider()
            Button("Channel Info…") { showsInfo = true }
        }
        .sheet(isPresented: $showsInfo) { ChannelInfoView(channel: channel) }
    }

    private var guideEntries: [EPGEntry]? {
        #if DEBUG
        // IPTV_TESTNOEPG=<channel id>: that channel has no listings.
        if ProcessInfo.processInfo.environment["IPTV_TESTNOEPG"] == String(channel.id) { return [] }
        #endif
        return guide.entries
    }

    /// Hatched bar for a channel without listings; it still plays (double-click).
    private var noData: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(.fill.quinary)
            .overlay { Hatching().clipShape(RoundedRectangle(cornerRadius: 7)) }
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.separator, lineWidth: 1) }
            .frame(width: GuideLayout.timelineWidth - 4, height: GuideLayout.rowHeight - 8)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("No program data").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    Text("The channel plays anyway · double-click to watch").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.leading, GuideLayout.channelWidth + 10)
                .stickyLeading()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { app.play(channel) }
            .padding(.leading, GuideLayout.channelWidth + 2)
            .padding(.top, 4)
    }

    /// Full-width bar while loading or without data; the text stays in view.
    private func placeholder(_ text: String?) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.fill.quinary)
            .frame(width: GuideLayout.timelineWidth - 4, height: GuideLayout.rowHeight - 6)
            .overlay(alignment: .leading) {
                if let text {
                    Text(text).font(.caption).foregroundStyle(.tertiary)
                        .padding(.leading, GuideLayout.channelWidth + 10)
                        .stickyLeading()
                }
            }
            .padding(.leading, GuideLayout.channelWidth + 2)
            .padding(.top, 3)
    }
}

private struct GuideCell: View {
    let entry: EPGEntry
    let now: Date
    let width: CGFloat
    let selected: Bool
    let recording: Recording.Status?

    var body: some View {
        let running = entry.start <= now && entry.end > now
        let past = entry.end <= now
        let mark = recording.flatMap { $0 == .skipped || $0 == .missed ? nil : $0 }
        VStack(alignment: .leading, spacing: 1) {
            if width > 28 {
                Text(verbatim: entry.title)
                    .font(.callout)
                    .fontWeight(running ? .semibold : .medium)
                    .foregroundStyle(past ? .tertiary : .primary)
                if width > 58 {
                    Text(secondLine(mark))
                        .font(.caption)
                        .fontWeight(mark == nil ? .regular : .semibold)
                        .monospacedDigit()
                        .foregroundStyle(mark != nil ? AnyShapeStyle(Theme.record) : past ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(width: max(0, width - 4), height: GuideLayout.rowHeight - 8, alignment: .leading)
        .visualEffect { [width] content, proxy in
            // Keep the title readable while the start has scrolled under the channel column.
            let hidden = GuideLayout.channelWidth - proxy.frame(in: .scrollView).minX
            return content.offset(x: min(max(0, hidden), max(0, width - 60)))
        }
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(past ? AnyShapeStyle(.fill.quinary) : running ? AnyShapeStyle(Color.accentColor.opacity(0.20)) : AnyShapeStyle(.fill.tertiary))
                if running {
                    // The part of the show that has already run.
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: max(0, width - 4) * entry.progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .overlay {
            if let mark {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.record, lineWidth: 1.5)
                if mark == .scheduled {
                    // Planned, not yet recording: a second, inner line.
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.record.opacity(0.55), lineWidth: 1).padding(3)
                }
            }
            if selected {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .padding(.top, 4)
        .padding(.leading, 2)
        .accessibilityLabel(accessibility(mark))
    }

    private var times: String {
        "\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))"
    }

    private func secondLine(_ mark: Recording.Status?) -> String {
        switch mark {
        case .scheduled?: return String(localized: "● Scheduled · \(times)")
        case .recording?: return String(localized: "● Recording · \(times)")
        case .done?, .failed?: return String(localized: "● Recorded · \(times)")
        default: return times
        }
    }

    private func accessibility(_ mark: Recording.Status?) -> String {
        [entry.title, secondLine(mark)].joined(separator: ", ")
    }
}

// MARK: - Detail

private struct GuideDetail: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    let entry: EPGEntry
    let close: () -> Void

    var body: some View {
        let running = entry.start <= Date() && entry.end > Date()
        HStack(alignment: .top, spacing: 18) {
            LogoTile(url: channel.icon, name: channel.displayName, width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(verbatim: entry.title).font(.title3.weight(.bold)).lineLimit(2)
                if running {
                    ProgressBar(value: entry.progress, height: 4).frame(maxWidth: 360)
                }
                if !entry.description.isEmpty {
                    Text(verbatim: entry.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                recordButton
                Button { app.play(channel) } label: {
                    Text("Watch").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help(running ? "On now" : "Watch the channel live")
            }
            .frame(width: 200)
            Button("Close", systemImage: "xmark") { close() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// "Aufnehmen" (R), or the way back once planned or running.
    @ViewBuilder
    private var recordButton: some View {
        if entry.end > Date() {
            let existing = recorder.recording(channelId: channel.id, entry: entry).flatMap { $0.isUpcomingOrRunning ? $0 : nil }
            Button {
                if let existing {
                    recorder.stop(existing.id)
                } else {
                    recorder.schedule(entry, on: channel).present()
                }
            } label: {
                HStack(spacing: 7) {
                    Circle().fill(.white).frame(width: 8, height: 8)
                    Text(existing == nil ? "Record" : existing?.status == .recording ? "Stop Recording" : "Remove Recording")
                    if existing == nil { Text(verbatim: "R").opacity(0.7) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.record)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: [])
        }
    }

    /// "Lichtspiel · Heute 22:55–23:45 · in 20 Min."
    private var caption: String {
        let times = "\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))"
        let day = Calendar.current.isDateInToday(entry.start) ? String(localized: "Today")
            : Calendar.current.isDateInTomorrow(entry.start) ? String(localized: "Tomorrow")
            : entry.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let now = Date()
        let relative: String
        if entry.start > now {
            let minutes = Int(entry.start.timeIntervalSince(now) / 60)
            relative = minutes < 60 ? String(localized: "in \(max(1, minutes)) min")
                : String(localized: "in \(minutes / 60) h \(minutes % 60) min")
        } else if entry.end > now {
            relative = String(localized: "running for \(Int(now.timeIntervalSince(entry.start) / 60)) min")
        } else {
            relative = String(localized: "over")
        }
        return [channel.displayName, "\(day) \(times)", relative].joined(separator: " · ")
    }
}

/// Diagonal stripes for rows without listings.
private struct Hatching: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 14
            }
            context.stroke(path, with: .style(.primary.opacity(0.05)), lineWidth: 7)
        }
        .allowsHitTesting(false)
    }
}
