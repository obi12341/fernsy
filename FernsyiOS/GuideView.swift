import FernsyCore
import SwiftUI

/// Live TV's guide (ios-app "Program guide"): the source's channels on a time axis that scrolls
/// sideways by touch, the channel column fixed at the left, the current time marked. A running
/// show plays its channel, a later one shows its details, a past one of an archive channel plays
/// from the archive; rows without listings show bars that play the channel.
struct GuideView: View {
    @EnvironmentObject private var model: TVModel
    @State private var asked: (show: EPGEntry, channel: LiveChannel)?
    @State private var position = ScrollPosition()
    /// The horizontal offset, for the channel column only: held, not observed (a @StateObject
    /// would redraw the whole guide on every frame of scrolling).
    @State private var scroll = GuideScroll()
    /// The part of the axis rows draw, in blocks of `block` hours around what is on screen.
    @State private var hours: ClosedRange<Int> = 0...0
    static let block = 6

    /// Points per hour on the axis.
    static let hourWidth: CGFloat = 220
    static let rowHeight: CGFloat = 64
    static let channelColumn: CGFloat = 76
    static let hourBar: CGFloat = 28
    /// The axis runs from the earliest archive day (or half an hour ago) to twelve hours ahead.
    static let ahead: TimeInterval = 12 * 3600

    static func defaultStart(_ now: Date = Date()) -> Date {
        let half = (now.timeIntervalSince1970 / 1800).rounded(.down) * 1800
        return Date(timeIntervalSince1970: half - 1800)
    }

    var body: some View {
        let channels = model.channels(for: model.liveSource)
        let reach = Archive.reach(of: channels)
        let start = reach > 0 ? Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(reach) * 86_400)) : Self.defaultStart()
        let end = Date().addingTimeInterval(Self.ahead)
        let width = CGFloat(end.timeIntervalSince(start) / 3600) * Self.hourWidth
        let window = max(start, start.addingTimeInterval(Double(hours.lowerBound) * 3600))...min(end, start.addingTimeInterval(Double(hours.upperBound) * 3600))
        // Sideways outside, up and down inside (ios-guide-performance): the inner scroll view has
        // the screen's height, so its lazy stack builds only the rows on screen, which load their
        // listings then; each row draws only `window`. (A vertical scroll view outside, or one
        // for both directions, measures the stack with unbounded height and builds every row.)
        ScrollView(.horizontal) {
            ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(channels) { channel in
                        ZStack(alignment: .topLeading) {
                            GuideRow(channel: channel, guide: model.guide.guide(channel.id), start: start, end: end, window: window) { show in
                                select(show, on: channel)
                            } play: { play(channel) }
                            .equatable()
                            .padding(.leading, Self.channelColumn)
                            // The channel column stays at the left edge while the axis scrolls sideways.
                            PinnedColumn(scroll: scroll) {
                                Button { play(channel) } label: {
                                    ChannelLogo(channel: channel).frame(width: 60, height: 38)
                                        .frame(width: Self.channelColumn, height: Self.rowHeight)
                                        .background(TVTheme.background)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: channel.displayName))
                            }
                        }
                    }
                } header: {
                    ZStack(alignment: .topLeading) {
                        hourBar(start: start, end: end, window: window).padding(.leading, Self.channelColumn)
                        PinnedColumn(scroll: scroll) {
                            Color.clear.frame(width: Self.channelColumn, height: Self.hourBar).background(TVTheme.background)
                        }
                    }
                }
            }
            .frame(width: Self.channelColumn + width, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
            scroll.x = rect.minX
            // Rounded out to blocks of hours with a screen's margin: rows filter again only every
            // few hours of scrolling, not on every frame.
            let block = CGFloat(Self.block) * Self.hourWidth
            let lower = Int(((rect.minX - rect.width) / block).rounded(.down)) * Self.block
            let upper = Int(((rect.maxX + rect.width) / block).rounded(.up)) * Self.block
            if lower...upper != hours { hours = lower...upper }
        }
        .task(id: start) {
            // Opens half an hour before now; after the first layout, so the axis is there.
            try? await Task.sleep(for: .milliseconds(50))
            position.scrollTo(x: CGFloat(Self.defaultStart().timeIntervalSince(start) / 3600) * Self.hourWidth)
        }
        .background(TVTheme.background.ignoresSafeArea())
        .sheet(isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } })) {
            if let asked { ShowDetailSheet(show: asked.show, channel: asked.channel) }
        }
        .accessibilityIdentifier("guide")
    }

    /// The half hours of `window` only: labels across the whole axis (days of archive) are drawn
    /// as one huge text layer.
    private func hourBar(start: Date, end: Date, window: ClosedRange<Date>) -> some View {
        let first = max(0, Int(window.lowerBound.timeIntervalSince(start) / 1800))
        let last = min(Int(end.timeIntervalSince(start) / 1800), Int(window.upperBound.timeIntervalSince(start) / 1800) + 1)
        return ZStack(alignment: .topLeading) {
            ForEach(first..<max(first, last), id: \.self) { i in
                let time = start.addingTimeInterval(Double(i) * 1800)
                Text(time, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(TVTheme.tertiary)
                    .offset(x: CGFloat(i) * Self.hourWidth / 2 + 4, y: 6)
            }
        }
        .frame(width: CGFloat(end.timeIntervalSince(start) / 3600) * Self.hourWidth, height: Self.hourBar, alignment: .topLeading)
        .overlay(alignment: .topLeading) { NowLine(start: start) }
        .background(TVTheme.background)
    }

    private func play(_ channel: LiveChannel) {
        model.zapSource = model.liveSource
        Task { await model.zap(to: channel) }
    }

    private func select(_ show: EPGEntry, on channel: LiveChannel) {
        let now = Date()
        if show.start <= now && now < show.end {
            play(channel)
        } else if show.end <= now && Archive.isPlayable(show, on: channel) {
            // A past show of an archive channel plays from its start (catch-up).
            Task { await model.playArchive(show, on: channel) }
        } else {
            asked = (show, channel)
        }
    }
}

/// Compared by channel and span only (the actions are the same for a channel): the guide redraws
/// when the visible span or the model changes, and unchanged rows are skipped then.
private struct GuideRow: View, Equatable {
    static func == (a: GuideRow, b: GuideRow) -> Bool {
        a.channel == b.channel && a.start == b.start && a.end == b.end && a.window == b.window
    }

    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    @ObservedObject var guide: ChannelGuide
    let start: Date
    let end: Date
    /// The part of the axis to draw (around what is on screen).
    let window: ClosedRange<Date>
    let select: (EPGEntry) -> Void
    /// A bar without listings plays the channel.
    let play: () -> Void

    var body: some View {
        let entries = listings
        let shows = (entries ?? []).filter { $0.end > window.lowerBound && $0.start < window.upperBound }
        let gaps = entries == nil ? [window] : GuideGaps.free(shows: shows, window: window)
        ZStack(alignment: .topLeading) {
            ForEach(shows, id: \.start) { show in
                Button { select(show) } label: {
                    GuideCell(show: show, archived: show.end <= Date() && Archive.isPlayable(show, on: channel))
                }
                .buttonStyle(.plain)
                .modifier(Placement(from: show.start, to: show.end, start: start, end: end))
                .accessibilityIdentifier("guide.\(channel.id).\(Int(show.start.timeIntervalSince1970))")
            }
            ForEach(gaps, id: \.lowerBound) { gap in
                Button(action: play) {
                    Text(entries == nil ? "Loading program …" : "No program data")
                        .font(.caption).lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 8))
                        .foregroundStyle(TVTheme.tertiary)
                }
                .buttonStyle(.plain)
                .modifier(Placement(from: gap.lowerBound, to: gap.upperBound, start: start, end: end))
                .accessibilityIdentifier("guide.\(channel.id).gap.\(Int(gap.lowerBound.timeIntervalSince1970))")
            }
            NowLine(start: start)
        }
        .frame(height: GuideView.rowHeight, alignment: .topLeading)
        #if DEBUG
        // Counted by the guide scrolling test (ios-guide-performance): rows built, not only shown.
        .onAppear { AppLog.detail(.guide, "guide row \(channel.id) appears") }
        #endif
        .task(id: channel.id) { await model.loadGuide(for: channel) }
        .task(id: "\(channel.id).\(Int(window.lowerBound.timeIntervalSince1970 / 86_400))") {
            // An archive channel's past days, once scrolled to: their programme from back then (catch-up).
            guard channel.archiveDays > 0, window.lowerBound < Date().addingTimeInterval(-3 * 3600) else { return }
            await model.guide.loadPast(channel.id, client: model.client, from: window.lowerBound)
        }
    }

    /// The channel's listings; none for `IPTV_TESTNOEPG=<channel id>` (debug), as on the Mac.
    private var listings: [EPGEntry]? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_TESTNOEPG"] == String(channel.id) { return [] }
        #endif
        return guide.entries
    }
}

/// The guide's horizontal scroll offset, observed only by the pinned channel column.
private final class GuideScroll: ObservableObject {
    @Published var x: CGFloat = 0
}

/// Content kept at the left edge of the guide: moved right by the horizontal offset, above the
/// shows scrolling under it.
private struct PinnedColumn<Content: View>: View {
    @ObservedObject var scroll: GuideScroll
    @ViewBuilder let content: Content

    var body: some View {
        content.offset(x: max(0, scroll.x)).zIndex(1)
    }
}

/// The current time on the axis.
private struct NowLine: View {
    let start: Date

    var body: some View {
        let offset = Date().timeIntervalSince(start)
        if offset > 0 {
            Capsule().fill(Color(hex: 0xFF4D45))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .offset(x: CGFloat(offset / 3600) * GuideView.hourWidth)
                .allowsHitTesting(false)
        }
    }
}

/// A cell's place on the time axis, clipped to the axis.
private struct Placement: ViewModifier {
    let from: Date, to: Date, start: Date, end: Date

    func body(content: Content) -> some View {
        let a = max(from, start), b = min(to, end)
        let x = CGFloat(a.timeIntervalSince(start) / 3600) * GuideView.hourWidth
        let width = CGFloat(b.timeIntervalSince(a) / 3600) * GuideView.hourWidth
        content.frame(width: max(width - 4, 12), height: GuideView.rowHeight - 6).offset(x: x + 2, y: 3)
    }
}

private struct GuideCell: View {
    let show: EPGEntry
    var archived = false

    var body: some View {
        let now = Date()
        let running = show.start <= now && now < show.end
        let past = show.end <= now
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: show.title).font(.footnote.weight(.semibold)).lineLimit(1)
            HStack(spacing: 4) {
                if archived { Image(systemName: "play.circle.fill").accessibilityHidden(true) }
                Text(show.start, format: .dateTime.hour().minute())
            }
            .font(.caption2).opacity(0.62).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                running ? TVTheme.accentLight.opacity(0.14) : past ? Color.white.opacity(0.03) : Color.white.opacity(0.08)
                if running {
                    GeometryReader { geo in
                        TVTheme.accentLight.opacity(0.16)
                            .frame(width: geo.size.width * min(1, now.timeIntervalSince(show.start) / show.end.timeIntervalSince(show.start)))
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .foregroundStyle(past ? TVTheme.text.opacity(0.5) : TVTheme.text)
    }
}
