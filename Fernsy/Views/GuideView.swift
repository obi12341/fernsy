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

    struct Selection: Equatable {
        let channelId: Int
        let entry: EPGEntry
        static func == (a: Self, b: Self) -> Bool { a.channelId == b.channelId && a.entry.id == b.entry.id }
    }

    @State private var origin = GuideLayout.origin(for: Date())
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
        .task {
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
            ToolbarItem {
                Button("Jetzt", systemImage: "clock") { scrollToNow() }
                    .help("Zur aktuellen Uhrzeit springen")
            }
        }
        .navigationTitle("Live TV")
        .navigationSubtitle("\(channels.count) Sender")
    }

    private func scrollToNow() {
        let now = Date()
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
    static let channelWidth: CGFloat = 170
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
        if Calendar.current.isDateInToday(time) { return String(localized: "Heute") }
        if Calendar.current.isDateInTomorrow(time) { return String(localized: "Morgen") }
        if Calendar.current.isDateInYesterday(time) { return String(localized: "Gestern") }
        return time.formatted(.dateTime.weekday(.wide).day().month())
    }
}

/// The red "now" line. The sticky channel column is drawn above it and covers it.
private struct NowMarker: View {
    let x: CGFloat

    var body: some View {
        Rectangle().fill(.red).frame(width: 2).padding(.leading, max(0, x - 1))
    }
}

// MARK: - Row

private struct GuideRow: View {
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
            if let entries = guide.entries {
                if !entries.contains(where: { $0.end > origin && $0.start < end }) {
                    placeholder("Keine Programminformationen")
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
                                Button("Abspielen") { app.play(channel) }
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
            RemoteImage(url: channel.icon, maxPixel: 96, contentMode: .fit) {
                Image(systemName: "tv").foregroundStyle(.tertiary)
            }
            .frame(width: 40, height: 26)
            Text(channel.name)
                .font(.callout)
                .fontWeight(isPlaying ? .semibold : .regular)
                .lineLimit(2)
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
            Button("Abspielen") { app.play(channel) }
            ChannelVisibilityButton(channel: channel)
        }
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
        VStack(alignment: .leading, spacing: 2) {
            if width > 28 {
                HStack(spacing: 4) {
                    if let recording, recording != .skipped && recording != .missed {
                        Image(systemName: recording == .scheduled ? "record.circle" : "record.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel(recording == .scheduled ? "Aufnahme geplant" : "Aufgenommen")
                    }
                    Text(entry.title)
                        .font(.callout)
                        .fontWeight(running ? .semibold : .regular)
                        .foregroundStyle(past ? .secondary : .primary)
                }
                Text(entry.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(width: max(0, width - 2), height: GuideLayout.rowHeight - 6, alignment: .leading)
        .visualEffect { [width] content, proxy in
            // Keep the title readable while the start has scrolled under the channel column.
            let hidden = GuideLayout.channelWidth - proxy.frame(in: .scrollView).minX
            return content.offset(x: min(max(0, hidden), max(0, width - 60)))
        }
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(running ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.fill.tertiary))
                .opacity(past ? 0.55 : 1)
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .padding(.top, 3)
    }
}

// MARK: - Detail

private struct GuideDetail: View {
    @EnvironmentObject private var app: AppModel
    let channel: LiveChannel
    let entry: EPGEntry
    let close: () -> Void

    var body: some View {
        let running = entry.start <= Date() && entry.end > Date()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(channel.name).font(.headline).lineLimit(1)
                Text(timeText).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                RecordButton(channel: channel, entry: entry)
                    .controlSize(.small)
                Button("Abspielen", systemImage: "play.fill") { app.play(channel) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help(running ? "Läuft gerade" : "Sender live abspielen")
                Button("Schließen", systemImage: "xmark") { close() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Text(entry.title).font(.title3).fontWeight(.semibold).lineLimit(2)
            if running {
                ProgressView(value: entry.progress).progressViewStyle(.linear)
            }
            if !entry.description.isEmpty {
                Text(entry.description).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(14)
        .background(.bar)
    }

    private var timeText: String {
        let times = "\(entry.start.formatted(date: .omitted, time: .shortened)) – \(entry.end.formatted(date: .omitted, time: .shortened))"
        if Calendar.current.isDateInToday(entry.start) { return times }
        return entry.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + "  " + times
    }
}
