import AppIntents
import Combine
import FernsyCore
import FernsyPlayer
import SwiftUI

// MARK: - Controls

struct PlayerControls: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var progress: PlaybackProgress
    let item: PlayItem
    /// The live channel's programme (empty for films).
    var entries: [EPGEntry] = []
    @Binding var showInfo: Bool
    let isFullScreen: Bool
    /// Hidden while the channel banner shows the same information.
    let showsTitle: Bool
    let onZap: (Int) -> Void
    let onFullScreen: () -> Void
    var onChannelList: () -> Void = {}
    let onActivity: () -> Void
    /// Live: the end of the recording running on this channel; nil when none runs.
    var recordingEnd: Date? = nil
    /// Live: recording is possible here.
    var canRecord = false
    var onRecord: () -> Void = {}
    /// Menu picks go through the screen, which remembers them for the series.
    var onPickAudio: (MediaTrack) -> Void = { _ in }
    var onPickSubtitle: (MediaTrack?) -> Void = { _ in }
    /// A slider drag starts (true) or ends (false); reported before the activity.
    var onDragging: (Bool) -> Void = { _ in }
    var pipPossible = false
    var onPictureInPicture: () -> Void = {}

    private var channel: LiveChannel? {
        if case .live(let id, _) = item.kind { return app.channel(id) }
        return nil
    }

    private var current: EPGEntry? { entries.first { $0.start <= Date() && $0.end > Date() } }
    private var next: EPGEntry? { entries.first { $0.start >= (current?.end ?? Date()) } }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .top, endPoint: .bottom).frame(height: 170)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(0.38)], startPoint: .top, endPoint: .bottom).frame(height: 260)
            }
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    captionPill.opacity(showsTitle ? 1 : 0)
                    Spacer()
                    if let recordingEnd { recordingPill(until: recordingEnd) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 40)
                .allowsHitTesting(false)
                Spacer(minLength: 0)
                panel
            }
        }
    }

    // MARK: Caption

    private var captionPill: some View {
        HStack(spacing: 12) {
            if let channel {
                LogoTile(url: channel.icon, name: channel.displayName, width: 48)
            } else {
                RoundedRectangle(cornerRadius: 7).fill(Theme.logoTile).frame(width: 48, height: 30)
                    .overlay(Image(systemName: "play.fill").font(.caption).foregroundStyle(.white))
            }
            VStack(alignment: .leading, spacing: 2) {
                if let channel {
                    TaggedName(name: channel.parsed, font: .callout, weight: .semibold)
                } else {
                    Text(verbatim: item.title).font(.callout.weight(.semibold)).lineLimit(1)
                }
                if let current {
                    Text(verbatim: "\(current.title) · \(times(current))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if let subtitle = item.subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func recordingPill(until end: Date) -> some View {
        HStack(spacing: 7) {
            Circle().fill(.white).frame(width: 8, height: 8)
            Text("Recording · until \(end.formatted(date: .omitted, time: .shortened))")
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 11).frame(height: 26)
        .background(Theme.record, in: Capsule())
    }

    // MARK: Panel

    /// Timeshift: what can be played, from the oldest buffered second to the live edge.
    private var liveRange: ClosedRange<Double>? {
        guard engine.isTimeshift else { return nil }
        let end = progress.liveEnd - PlayerEngine.liveLead
        guard end - progress.liveStart > 10 else { return nil }
        return progress.liveStart...end
    }

    private var panel: some View {
        VStack(spacing: 12) {
            if item.isLive, let current {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    label("NOW")
                    Text(verbatim: current.title).fontWeight(.semibold).lineLimit(1)
                    Text("\(times(current)) · \(max(1, Int(current.end.timeIntervalSinceNow / 60))) min left")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Spacer(minLength: 12)
                    if let next {
                        label("NEXT")
                        Text(verbatim: "\(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.callout)
            }
            if let range = liveRange {
                LiveTimeline(progress: progress, range: range, entries: entries,
                             wallTime: { engine.wallTime(of: $0) },
                             onSeek: { engine.seek(to: $0) }, onGoLive: { engine.goLive() },
                             onDragging: onDragging, onActivity: onActivity)
            }
            if !item.isLive && progress.duration > 0 {
                FilmTimeline(progress: progress, onSeek: { engine.seek(to: $0) }, onDragging: onDragging, onActivity: onActivity)
                    .padding(.top, 4)
            }
            buttons
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 25, y: 18)
        .frame(maxWidth: 1100)
        .padding(.horizontal, 40)
        .padding(.bottom, 26)
        .onHover { if $0 { onActivity() } }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if item.isLive {
                roundButton("chevron.up", help: "Previous channel (↑)") { onZap(-1) }
                roundButton("chevron.down", help: "Next channel (↓)") { onZap(1) }
                roundButton("list.bullet", help: "Channel List (L)") { onChannelList() }
                Divider().frame(height: 20).padding(.horizontal, 4)
            }
            let seekable = !item.isLive || engine.isTimeshift
            if !item.isLive {
                textButton("−60", help: "1 min back (⇧←)") { engine.seek(by: -60) }
            }
            if seekable {
                textButton("−10", help: "Back 10 s (←)") { engine.seek(by: -10) }
            }
            Button {
                engine.togglePause()
                onActivity()
            } label: {
                Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.fill.secondary, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Play/Pause (Space)")
            if seekable {
                textButton("+10", help: "Forward 10 s (→)") { engine.seek(by: 10) }
                    .disabled(item.isLive && progress.followsLive)
                    .opacity(item.isLive && progress.followsLive ? 0.35 : 1)
            }
            if !item.isLive {
                textButton("+60", help: "1 min forward (⇧→)") { engine.seek(by: 60) }
            }
            if liveRange != nil { liveState.padding(.leading, 6) }

            Spacer()

            if canRecord {
                Button {
                    onRecord()
                    onActivity()
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(recordingEnd != nil ? .white : Theme.record).frame(width: 9, height: 9)
                        Text(recordingEnd != nil ? "Stop Recording" : "Record")
                        if recordingEnd == nil { Text(verbatim: "R").foregroundStyle(.secondary) }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(recordingEnd != nil ? .white : .primary)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(recordingEnd != nil ? AnyShapeStyle(Theme.record) : AnyShapeStyle(.fill.tertiary), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(recordingEnd != nil ? "Stop recording (R)" : "Record the current show (R)")
            }

            HStack(spacing: 6) {
                Button { engine.isMuted.toggle() } label: {
                    Image(systemName: volumeIcon).frame(width: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Mute (M)")
                Slider(value: Binding(get: { Double(engine.volume) }, set: { engine.volume = Float($0); onActivity() }), in: 0...1) { editing in
                    onDragging(editing)
                    onActivity()
                }
                .frame(width: 84)
                .controlSize(.mini)
            }
            .padding(.horizontal, 6)

            tracksMenu
            roundButton(showInfo ? "info.circle.fill" : "info", help: "Technical info (I)") { showInfo.toggle() }
            if pipPossible {
                roundButton("pip.enter", help: "Picture in Picture (P)") { onPictureInPicture() }
            }
            roundButton(isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        help: isFullScreen ? "Exit full screen (F, Esc)" : "Full screen (F)") { onFullScreen() }
        }
    }

    /// Red "LIVE" at the live edge; behind it the distance with a way back.
    @ViewBuilder
    private var liveState: some View {
        if progress.followsLive {
            StatusBadge(kind: .live)
        } else {
            Button {
                engine.goLive()
                onActivity()
            } label: {
                HStack(spacing: 8) {
                    Text("−" + formatTime(progress.behindLive)).font(.callout.weight(.bold)).monospacedDigit()
                    Text("TO LIVE ⇥")
                        .font(.caption2.weight(.bold))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 20)
                        .background(Theme.record, in: Capsule())
                }
                .padding(.leading, 11).padding(.trailing, 5).frame(height: 28)
                .background(.fill.tertiary, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Back to live")
        }
    }

    /// Audio and subtitle tracks in one menu.
    @ViewBuilder
    private var tracksMenu: some View {
        if let media = engine.media, media.audioTracks.count > 1 || !media.subtitleTracks.isEmpty {
            Menu {
                if media.audioTracks.count > 1 {
                    Picker("Audio Track", selection: Binding(
                        get: { media.selectedAudio },
                        set: { id in if let track = media.audioTracks.first(where: { $0.id == id }) { onPickAudio(track) } }
                    )) {
                        ForEach(media.audioTracks) { track in Text(track.title).tag(Optional(track.id)) }
                    }
                    .pickerStyle(.inline)
                }
                if !media.subtitleTracks.isEmpty {
                    Picker("Subtitles", selection: Binding(
                        get: { media.selectedSubtitle },
                        set: { id in onPickSubtitle(media.subtitleTracks.first { $0.id == id }) }
                    )) {
                        Text("Off").tag(Int32?.none)
                        ForEach(media.subtitleTracks) { track in Text(track.title).tag(Optional(track.id)) }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Text("Audio & Subtitles")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(media.selectedSubtitle != nil ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary), in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Audio track and subtitles")
        }
    }

    // MARK: Pieces

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.tertiary)
    }

    private func times(_ entry: EPGEntry) -> String {
        "\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))"
    }

    private var volumeIcon: String {
        if engine.isMuted || engine.volume == 0 { return "speaker.slash.fill" }
        if engine.volume < 0.34 { return "speaker.wave.1.fill" }
        if engine.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func roundButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onActivity()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(.fill.tertiary, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func textButton(_ title: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onActivity()
        } label: {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 10).frame(height: 32)
                .background(.fill.tertiary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
