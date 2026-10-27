import FernsyCore
import SwiftUI

/// The guide (design screen `guide`, design G of tvos-live): three hours of a source's channels
/// on a time axis with the current time marked. A running show plays its channel, a later one
/// offers to record it; moving past the window's edge pages it by an hour.
struct GuideScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var source: TVModel.LiveSource?
    @State private var windowStart = GuideScreen.defaultStart()
    @State private var asked: (show: EPGEntry, channel: LiveChannel)?

    static let span: TimeInterval = 3 * 3600
    /// Points per second on the axis: 1440 points for three hours, as in the design.
    static let axisWidth: CGFloat = 1440
    static let channelColumn: CGFloat = 300

    /// Half an hour before the current half hour.
    static func defaultStart(_ now: Date = Date()) -> Date {
        let half = (now.timeIntervalSince1970 / 1800).rounded(.down) * 1800
        return Date(timeIntervalSince1970: half - 1800)
    }

    private var current: TVModel.LiveSource {
        source ?? (model.channels(for: .favorites).isEmpty ? .all : .favorites)
    }

    var body: some View {
        let channels = model.channels(for: current)
        VStack(alignment: .leading, spacing: 0) {
            header
            hours.padding(.leading, Self.channelColumn).padding(.top, 26)
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
            .focusSection()
        }
        .padding(.horizontal, 90)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TVTheme.background)
        .foregroundStyle(TVTheme.text)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(dayTitle).font(.system(size: 44, weight: .bold))
            Menu {
                Button("Favorites") { source = .favorites }
                Button("Recently Watched") { source = .recent }
                Button("All Channels") { source = .all }
                ForEach(model.pinnedCategories) { category in
                    Button(category.displayName) { source = .category(category.id) }
                }
            } label: {
                Text("\(sourceName) · \(TimeSpan.of(windowStart, windowStart.addingTimeInterval(Self.span)))")
                    .font(.system(size: 26))
            }
            .accessibilityIdentifier("guide.source")
        }
        .focusSection()
    }

    private var dayTitle: LocalizedStringKey {
        Calendar.current.isDateInToday(windowStart) ? "Today" : Calendar.current.isDateInTomorrow(windowStart) ? "Tomorrow" : "Yesterday"
    }

    private var sourceName: String {
        switch current {
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
            model.zapSource = current
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
        case .left where show.start <= windowStart: windowStart = windowStart.addingTimeInterval(-3600)
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
