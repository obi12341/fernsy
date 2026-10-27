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
    @State private var asked: (show: EPGEntry, channel: LiveChannel)?
    @FocusState private var railFocused: Bool
    @FocusState private var focusedEntry: TVModel.LiveSource?

    static let span: TimeInterval = 3 * 3600
    /// Points for three hours on the axis (the design's 1440, less the rail's width).
    static let axisWidth: CGFloat = 1380
    static let channelColumn: CGFloat = 300
    static let railWidth: CGFloat = 80

    /// Half an hour before the current half hour.
    static func defaultStart(_ now: Date = Date()) -> Date {
        let half = (now.timeIntervalSince1970 / 1800).rounded(.down) * 1800
        return Date(timeIntervalSince1970: half - 1800)
    }

    var body: some View {
        let source = model.liveSource
        let channels = model.channels(for: source)
        HStack(alignment: .top, spacing: 16) {
            rail
            VStack(alignment: .leading, spacing: 0) {
                header
                hours.padding(.leading, Self.channelColumn).padding(.top, 20)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(channels) { channel in
                            GuideRow(channel: channel, guide: model.guide.guide(channel.id), windowStart: $windowStart) { show in
                                select(show, on: channel)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .overlay(alignment: .topLeading) { nowLine }
                // Rows and the now line run to the screen's edge, under the bottom safe area.
                .ignoresSafeArea(edges: .bottom)
                .focusSection()
            }
        }
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(dayTitle).font(.system(size: 44, weight: .bold))
            Text("\(sourceName) · \(TimeSpan.of(windowStart, windowStart.addingTimeInterval(Self.span)))")
                .font(.system(size: 26))
                .foregroundStyle(TVTheme.secondary)
                .accessibilityIdentifier("guide.source")
        }
    }

    private var dayTitle: LocalizedStringKey {
        Calendar.current.isDateInToday(windowStart) ? "Today" : Calendar.current.isDateInTomorrow(windowStart) ? "Tomorrow" : "Yesterday"
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
    let select: (EPGEntry) -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                ChannelLogo(channel: channel).frame(width: 116, height: 72)
                Text(verbatim: channel.displayName).font(.system(size: 22, weight: .semibold)).lineLimit(1)
            }
            .frame(width: GuideScreen.channelColumn - 16, alignment: .leading)
            ZStack(alignment: .topLeading) {
                let windowEnd = windowStart.addingTimeInterval(GuideScreen.span)
                let shows = (guide.entries ?? []).filter { $0.end > windowStart && $0.start < windowEnd }
                if shows.isEmpty {
                    Text(guide.entries == nil ? "Loading programme …" : "No programme information")
                        .font(.system(size: 21)).foregroundStyle(TVTheme.tertiary)
                        .frame(maxHeight: .infinity)
                }
                ForEach(shows, id: \.start) { show in
                    let from = max(show.start, windowStart), to = min(show.end, windowEnd)
                    let x = CGFloat(from.timeIntervalSince(windowStart) / GuideScreen.span) * GuideScreen.axisWidth
                    let width = CGFloat(to.timeIntervalSince(from) / GuideScreen.span) * GuideScreen.axisWidth
                    Button { select(show) } label: {
                        GuideCell(show: show, recorded: model.isScheduled(show, on: channel) || isRecordedNow(show))
                    }
                    .buttonStyle(GuideCellStyle())
                    .frame(width: max(width - 8, 30), height: 104)
                    .offset(x: x + 4)
                    .onMoveCommand { direction in page(direction, show: show, windowEnd: windowEnd) }
                    .accessibilityIdentifier("guide.\(channel.id).\(Int(show.start.timeIntervalSince1970))")
                    .accessibilityValue(model.isScheduled(show, on: channel) ? "scheduled" : "")
                }
            }
            .frame(width: GuideScreen.axisWidth, height: 104, alignment: .topLeading)
        }
        .task(id: channel.id) { await model.loadGuide(for: channel) }
    }

    private func isRecordedNow(_ show: EPGEntry) -> Bool {
        guard let active = model.activeRecording(on: channel) else { return false }
        return active.start < show.end && active.end > show.start
    }

    /// At the window's edge, Right and Left page it by an hour (the cell stays focusable).
    private func page(_ direction: MoveCommandDirection, show: EPGEntry, windowEnd: Date) {
        switch direction {
        case .right where show.end >= windowEnd: windowStart = windowStart.addingTimeInterval(3600)
        // Back only to the window it opens with: from there Left goes on to the rail.
        case .left where show.start <= windowStart && windowStart > GuideScreen.defaultStart():
            windowStart = windowStart.addingTimeInterval(-3600)
        default: break
        }
    }
}

private struct GuideCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private struct GuideCell: View {
    let show: EPGEntry
    let recorded: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        let now = Date()
        let running = show.start <= now && now < show.end
        let past = show.end <= now
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: show.title).font(.system(size: 23, weight: .semibold)).lineLimit(1)
            HStack(spacing: 8) {
                if recorded { Circle().fill(Color(hex: 0xFF4D45)).frame(width: 10, height: 10) }
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
