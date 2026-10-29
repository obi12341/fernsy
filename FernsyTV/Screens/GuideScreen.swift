import FernsyCore
import SwiftUI

/// Live TV's guide view (design screen `guide`, design G of tvos-live; tvos-live-and-guide):
/// three hours of the source's channels on a time axis with the current time marked. A running
/// show plays its channel, a later one offers to record it; moving past the window's edge pages
/// it by an hour. The category column narrows to a rail; clicking it opens the column over the
/// grid.
struct GuideScreen: View {
    @EnvironmentObject private var model: TVModel
    @Binding var columnOpen: Bool
    @Binding var showAll: Bool
    @State private var windowStart = GuideScreen.defaultStart()
    /// The start the guide gave the window itself; a different `windowStart` was paged by the user.
    @State private var placedStart = GuideScreen.defaultStart()
    @State private var hiddenSince: Date?
    @Environment(\.scenePhase) private var scenePhase
    @State private var asked: (show: EPGEntry, channel: LiveChannel)?
    @FocusState private var railFocused: Bool
    @FocusState private var focusedEntry: TVModel.LiveSource?

    static let span: TimeInterval = 3 * 3600
    /// Points for three hours on the axis (the design's 1440, less the rail's width).
    static let axisWidth: CGFloat = 1380
    static let channelColumn: CGFloat = 300
    static let railWidth: CGFloat = 80

    /// Half an hour before the current half hour.
    static func defaultStart(_ now: Date = Date()) -> Date { GuideWindow.start(at: now) }

    var body: some View {
        let source = model.liveSource
        let channels = model.channels(for: source)
        // Left reaches back as far as the shown channels' longest archive (catch-up).
        let reach = Archive.reach(of: channels)
        let earliest = reach > 0 ? Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(reach) * 86_400)) : Self.defaultStart()
        HStack(alignment: .top, spacing: 16) {
            rail
            VStack(alignment: .leading, spacing: 0) {
                header
                hours.padding(.leading, Self.channelColumn).padding(.top, 20)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(channels) { channel in
                            GuideRow(channel: channel, guide: model.guide.guide(channel.id), windowStart: $windowStart, earliest: earliest) { show in
                                select(show, on: channel)
                            } play: {
                                model.zapSource = model.liveSource
                                model.play(channel)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .overlay(alignment: .topLeading) { nowLine }
                // Rows and the now line run to the screen's edge, under the bottom safe area.
                .ignoresSafeArea(edges: .bottom)
                .focusSection()
                // Back returns a paged window to now, then goes to the rail: Left pages into the
                // archive and may not reach it (tvos-guide-back-to-rail). Back on the rail goes on
                // to the tab bar.
                .onExitCommand {
                    if windowStart != Self.defaultStart() { place(Self.defaultStart()) } else { railFocused = true }
                }
            }
        }
        // The window follows now (GuideWindow): checked each minute, and when the guide comes back
        // into sight (tvOS keeps the app, and Live TV keeps the guide, for hours).
        .task {
            while !Task.isCancelled {
                followNow()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { followNow() } else if hiddenSince == nil { hiddenSince = Date() }
        }
        .onAppear { followNow() }
        .onDisappear { hiddenSince = hiddenSince ?? Date() }
        .disabled(columnOpen)
        .overlay { if columnOpen { Color.black.opacity(0.5).padding(-40).allowsHitTesting(false) } }
        .overlay(alignment: .topLeading) { if columnOpen { column } }
        .padding(.leading, 80)
        .padding(.trailing, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(asked.map { $0.show.title } ?? "", isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } }),
                            presenting: asked) { item in
            if model.isScheduled(item.show, on: item.channel) {
                Button("Don’t Record", role: .destructive) { model.recorder.unschedule(channelId: item.channel.id, entry: item.show) }
            } else {
                Button("Record") { model.notice = model.schedule(item.show, on: item.channel) }
            }
        } message: { item in
            Text("\(item.channel.displayName) · \(TimeSpan.of(item.show)). Records only while Fernsy is open.")
        }
    }

    /// The collapsed category column: the source's name, read top to bottom.
    private var rail: some View {
        Button(action: openColumn) {
            VStack(spacing: 22) {
                Image(systemName: "list.bullet").font(.system(size: 26, weight: .semibold))
                Text(verbatim: sourceName)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 560, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: 40, height: 560)
            }
            .padding(.vertical, 26)
            .frame(width: Self.railWidth)
        }
        .buttonStyle(TVTileStyle(rest: Color.white.opacity(0.06), radius: 18, scale: 1.03))
        // While the window is paged ahead, Left at its edge pages back instead of leaving the grid.
        .disabled(windowStart > Self.defaultStart())
        .focused($railFocused)
        .accessibilityIdentifier("rail.source")
        .accessibilityValue(sourceName)
    }

    /// The category column opened over the grid; a click chooses and closes it, Right or Back
    /// closes it without a change.
    private var column: some View {
        CategoryColumn(focus: $focusedEntry,
                       choose: { model.chooseLiveSource($0); closeColumn() },
                       showAll: { closeColumn(); showAll = true })
            .frame(width: 330)
            .padding(20)
            .background(Color(hex: 0x1C1B22), in: .rect(cornerRadius: 26))
            .shadow(color: .black.opacity(0.6), radius: 40, x: 20)
            .onExitCommand { closeColumn() }
            .onMoveCommand { if $0 == .right { closeColumn() } }
            // A container of its own: an identifier on the column alone would replace its entries'.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rail.column")
    }

    private func openColumn() {
        columnOpen = true
        let source = model.liveSource
        // The column lists the chosen source (an unpinned category too); its entries exist
        // from the next update on.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            focusedEntry = source
        }
    }

    private func closeColumn() {
        columnOpen = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            railFocused = true
        }
    }

    private func followNow() {
        let hiddenFor = hiddenSince.map { Date().timeIntervalSince($0) } ?? 0
        hiddenSince = nil
        guard let start = GuideWindow.update(current: windowStart, placed: placedStart, span: Self.span, hiddenFor: hiddenFor) else { return }
        AppLog.detail(.app, "guide window to now: \(start.formatted(date: .omitted, time: .shortened))")
        place(start)
    }

    private func place(_ start: Date) {
        windowStart = start
        placedStart = start
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(verbatim: dayTitle).font(.system(size: 44, weight: .bold)).accessibilityIdentifier("guide.day")
            Text("\(sourceName) · \(TimeSpan.of(windowStart, windowStart.addingTimeInterval(Self.span)))")
                .font(.system(size: 26))
                .foregroundStyle(TVTheme.secondary)
                .accessibilityIdentifier("guide.source")
        }
    }

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(windowStart) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(windowStart) { return String(localized: "Tomorrow") }
        if calendar.isDateInYesterday(windowStart) { return String(localized: "Yesterday") }
        return windowStart.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var sourceName: String {
        switch model.liveSource {
        case .favorites: String(localized: "Favorites")
        case .recent: String(localized: "Recently Watched")
        case .all: String(localized: "All Channels")
        case .category(let id): model.categories.first { $0.id == id }?.displayName ?? ""
        }
    }

    private var hours: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<6) { i in
                let time = windowStart.addingTimeInterval(Double(i) * 1800)
                Text(time, format: .dateTime.hour().minute())
                    .font(.system(size: 21).monospacedDigit())
                    .foregroundStyle(TVTheme.text.opacity(0.55))
                    .offset(x: CGFloat(i) * Self.axisWidth / 6)
            }
        }
        .frame(width: Self.axisWidth, height: 30, alignment: .topLeading)
    }

    @ViewBuilder private var nowLine: some View {
        let offset = Date().timeIntervalSince(windowStart)
        if offset > 0 && offset < Self.span {
            Capsule().fill(Color(hex: 0xFF4D45))
                .frame(width: 3)
                .offset(x: Self.channelColumn + CGFloat(offset / Self.span) * Self.axisWidth)
                .allowsHitTesting(false)
        }
    }

    private func select(_ show: EPGEntry, on channel: LiveChannel) {
        let now = Date()
        if show.start <= now && now < show.end {
            model.zapSource = model.liveSource
            model.play(channel)
        } else if show.start > now {
            asked = (show, channel)
        } else if Archive.isPlayable(show, on: channel) {
            // A past show of an archive channel plays from its start (catch-up).
            Task { await model.playArchive(show, on: channel) }
        }
    }
}

/// "20:15–21:00".
enum TimeSpan {
    static func of(_ show: EPGEntry) -> String { of(show.start, show.end) }

    static func of(_ start: Date, _ end: Date) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(start.formatted(style))–\(end.formatted(style))"
    }
}

private struct GuideRow: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    @ObservedObject var guide: ChannelGuide
    @Binding var windowStart: Date
    /// How far Left pages back: today's start, or the shown channels' archive.
    let earliest: Date
    let select: (EPGEntry) -> Void
    /// A bar without listings plays the channel (tvos-guide-empty-channels).
    let play: () -> Void
    /// The cell with focus, by its start: paging back keeps focus on it instead of letting it
    /// escape to the rail on the left (catch-up).
    @FocusState private var focused: Date?
    /// The cell with focus, kept while focus is in the row or left it together with that cell: when
    /// the cell vanishes because the row's programme arrived, focus goes to the cell now there
    /// (tvos-guide-focus-while-loading). Cleared when the user moves focus away.
    @State private var lastFocused: Date?

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                ChannelLogo(channel: channel).frame(width: 116, height: 72)
                Text(verbatim: channel.displayName).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                if channel.archiveDays > 0 { ArchiveMark(channel: channel) }
            }
            .frame(width: GuideScreen.channelColumn - 16, alignment: .leading)
            ZStack(alignment: .topLeading) {
                let windowEnd = windowStart.addingTimeInterval(GuideScreen.span)
                let entries = listings
                let shows = (entries ?? []).filter { $0.end > windowStart && $0.start < windowEnd }
                ForEach(shows, id: \.start) { show in
                    Button { select(show) } label: {
                        GuideCell(show: show, recorded: model.isScheduled(show, on: channel) || isRecordedNow(show),
                                  archived: show.end <= Date() && Archive.isPlayable(show, on: channel))
                    }
                    .buttonStyle(GuideCellStyle())
                    .focused($focused, equals: show.start)
                    .modifier(GuidePlacement(from: show.start, to: show.end, windowStart: windowStart, windowEnd: windowEnd))
                    .onMoveCommand { direction in page(direction, start: show.start, end: show.end, windowEnd: windowEnd) }
                    .accessibilityIdentifier("guide.\(channel.id).\(Int(show.start.timeIntervalSince1970))")
                    .accessibilityValue(model.isScheduled(show, on: channel) ? "scheduled" : "")
                }
                // Without listings (or still loading) and in gaps: bars that play the channel, so
                // focus reaches every row (tvos-guide-empty-channels).
                let gaps = entries == nil ? [windowStart...windowEnd] : GuideGaps.free(shows: shows, window: windowStart...windowEnd)
                ForEach(gaps, id: \.lowerBound) { gap in
                    Button(action: play) { GuideGapCell(loading: entries == nil) }
                        .buttonStyle(GuideCellStyle())
                        .focused($focused, equals: gap.lowerBound)
                        .modifier(GuidePlacement(from: gap.lowerBound, to: gap.upperBound, windowStart: windowStart, windowEnd: windowEnd))
                        .onMoveCommand { direction in page(direction, start: gap.lowerBound, end: gap.upperBound, windowEnd: windowEnd) }
                        .accessibilityIdentifier("guide.\(channel.id).gap.\(Int(gap.lowerBound.timeIntervalSince1970))")
                        .accessibilityValue(entries == nil ? "loading" : "empty")
                }
            }
            .frame(width: GuideScreen.axisWidth, height: 104, alignment: .topLeading)
        }
        .onChange(of: focused) { _, now in
            // The cell still drawn: the user moved on (Down, Left to the rail), so nothing to keep.
            if let now { lastFocused = now } else if let last = lastFocused, cellStarts.contains(last) { lastFocused = nil }
        }
        .onChange(of: cellStarts) { old, new in keepFocus(old: old, new: new) }
        .task(id: channel.id) { await model.loadGuide(for: channel) }
        // A past day of an archive channel: its programme from back then (catch-up).
        .task(id: "\(channel.id).\(Int(windowStart.timeIntervalSince1970 / 3600))") {
            guard channel.archiveDays > 0, windowStart < Date().addingTimeInterval(-3 * 3600) else { return }
            await model.guide.loadPast(channel.id, client: model.client, from: windowStart)
        }
    }

    private func isRecordedNow(_ show: EPGEntry) -> Bool {
        guard let active = model.activeRecording(on: channel) else { return false }
        return active.start < show.end && active.end > show.start
    }

    /// The ids of the cells drawn: shows and bars, by their start.
    private var cellStarts: [Date] {
        let windowEnd = windowStart.addingTimeInterval(GuideScreen.span)
        guard let entries = listings else { return [windowStart] }
        let shows = entries.filter { $0.end > windowStart && $0.start < windowEnd }
        return shows.map(\.start) + GuideGaps.free(shows: shows, window: windowStart...windowEnd).map(\.lowerBound)
    }

    /// The focused cell vanished because the row's cells changed (its programme arrived): focus
    /// the cell covering now in the window, else the window's start, so focus stays in this row.
    private func keepFocus(old: [Date], new: [Date]) {
        guard let last = lastFocused, old.contains(last), !new.contains(last) else { return }
        // Focus is still on it, or left the row together with the cell (lastFocused survived).
        guard focused == last || focused == nil else { return }
        let windowEnd = windowStart.addingTimeInterval(GuideScreen.span)
        let now = Date()
        let reference = now > windowStart && now < windowEnd ? now : windowStart
        let entries = listings ?? []
        let target = entries.first { $0.start <= reference && $0.end > reference && new.contains($0.start) }?.start
            ?? new.filter { $0 <= reference }.max() ?? new.min()
        guard let target else { return }
        AppLog.detail(.app, "guide row \(channel.id): focus kept on the cell at \(target.formatted(date: .omitted, time: .shortened))")
        focused = target
    }

    /// The channel's listings; none for `IPTV_TESTNOEPG=<channel id>` (debug), as on the Mac.
    private var listings: [EPGEntry]? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_TESTNOEPG"] == String(channel.id) { return [] }
        #endif
        return guide.entries
    }

    /// At the window's edge, Right and Left page it by an hour (the cell stays focusable).
    private func page(_ direction: MoveCommandDirection, start: Date, end: Date, windowEnd: Date) {
        switch direction {
        case .right where end >= windowEnd: windowStart = windowStart.addingTimeInterval(3600)
        // Back only to the window it opens with: from there Left goes on to the rail.
        case .left where start <= windowStart && windowStart > earliest:
            windowStart = windowStart.addingTimeInterval(-3600)
            // The rail on the left would take the focus: give it back to this cell, now further right.
            DispatchQueue.main.async { focused = start }
        default: break
        }
    }
}

/// A cell's place on the time axis: from `from` to `to`, clipped to the window.
private struct GuidePlacement: ViewModifier {
    let from: Date, to: Date, windowStart: Date, windowEnd: Date

    func body(content: Content) -> some View {
        let start = max(from, windowStart), end = min(to, windowEnd)
        let x = CGFloat(start.timeIntervalSince(windowStart) / GuideScreen.span) * GuideScreen.axisWidth
        let width = CGFloat(end.timeIntervalSince(start) / GuideScreen.span) * GuideScreen.axisWidth
        content.frame(width: max(width - 8, 30), height: 104).offset(x: x + 4)
    }
}

/// A stretch without listings: hatched like the Mac's bar, "No program data" (or "Loading
/// program …"); clicking plays the channel.
private struct GuideGapCell: View {
    let loading: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        Text(loading ? "Loading program …" : "No program data")
            .font(.system(size: 21, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                if focused { TVTheme.focused } else {
                    Color.white.opacity(0.04).overlay { Hatching().opacity(0.06) }
                }
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay { if !focused { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)) } }
            .foregroundStyle(focused ? TVTheme.focusedText : TVTheme.tertiary)
            .scaleEffect(focused ? 1.04 : 1)
            .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 18, y: 18)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Diagonal stripes.
private struct Hatching: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 18
            }
            context.stroke(path, with: .color(.white), lineWidth: 6)
        }
    }
}

private struct GuideCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private struct GuideCell: View {
    let show: EPGEntry
    let recorded: Bool
    /// A past show in the channel's archive: it can be played (catch-up).
    var archived = false
    @Environment(\.isFocused) private var focused

    var body: some View {
        let now = Date()
        let running = show.start <= now && now < show.end
        let past = show.end <= now
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: show.title).font(.system(size: 23, weight: .semibold)).lineLimit(1)
            HStack(spacing: 8) {
                if recorded { Circle().fill(Color(hex: 0xFF4D45)).frame(width: 10, height: 10) }
                if archived { Image(systemName: "play.circle.fill").accessibilityHidden(true) }
                Text(focused ? TimeSpan.of(show) : show.start.formatted(.dateTime.hour().minute()))
            }
            .font(.system(size: 19)).opacity(0.62).lineLimit(1)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                (focused ? TVTheme.focused : running ? TVTheme.accentLight.opacity(0.14) : past ? Color.white.opacity(0.03) : Color.white.opacity(0.08))
                if running && !focused {
                    GeometryReader { geo in
                        TVTheme.accentLight.opacity(0.16)
                            .frame(width: geo.size.width * min(1, now.timeIntervalSince(show.start) / show.end.timeIntervalSince(show.start)))
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 14))
        .foregroundStyle(focused ? TVTheme.focusedText : past ? TVTheme.text.opacity(0.5) : TVTheme.text)
        .scaleEffect(focused ? 1.04 : 1)
        .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 18, y: 18)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
