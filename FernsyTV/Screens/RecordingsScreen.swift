import FernsyCore
import FernsyPlayer
import SwiftUI

/// Recordings (design screen `aufnahmen`): running and scheduled ones, then the recorded ones
/// (finished, failed, missed). Click plays a recording; a long press stops, unschedules or
/// deletes it.
struct RecordingsScreen: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        let all = model.recorder.recordings
        let upcoming = all.filter(\.isUpcomingOrRunning).sorted { $0.recordStart < $1.recordStart }
        let recorded = all.filter { !$0.isUpcomingOrRunning && $0.status != .skipped }.sorted { $0.recordStart > $1.recordStart }
        ScrollView {
            VStack(alignment: .leading, spacing: 46) {
                if all.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("No recordings yet").font(.system(size: 34, weight: .bold))
                        Text("Hold a channel’s button in Live TV or choose a show in the Guide to record it. Fernsy records while it is open on this Apple TV; tvOS may remove recordings when space runs short.")
                            .font(.system(size: 24)).foregroundStyle(TVTheme.secondary).frame(maxWidth: 1100, alignment: .leading)
                    }
                }
                if !upcoming.isEmpty {
                    let running = upcoming.filter { $0.status == .recording }.count
                    Shelf(title: "Running and Scheduled",
                          count: String(localized: "\(running) running · \(upcoming.count - running) scheduled"),
                          recordings: upcoming)
                }
                if !recorded.isEmpty {
                    Shelf(title: "Recorded", count: "\(recorded.count)", recordings: recorded)
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TVTheme.background)
        .foregroundStyle(TVTheme.text)
        .accessibilityIdentifier("recordings.screen")
    }
}

private struct Shelf: View {
    let title: LocalizedStringKey
    let count: String
    let recordings: [Recording]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title).font(.system(size: 30, weight: .bold))
                Text(verbatim: count).font(.system(size: 21)).foregroundStyle(TVTheme.text.opacity(0.55))
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 36) {
                    ForEach(recordings) { RecordingCard(recording: $0) }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

private struct RecordingCard: View {
    @EnvironmentObject private var model: TVModel
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card
            caption
        }
    }

    private var card: some View {
        Button {
            if recording.status == .scheduled { return }
            model.play(recording)
        } label: {
            CardImage(recording: recording, channel: model.channels.first { $0.id == recording.channelId })
        }
        .buttonStyle(.card)
        .contextMenu {
            switch recording.status {
            case .recording: Button("Stop Recording", systemImage: "stop.circle") { model.recorder.stop(recording.id) }
            case .scheduled: Button("Don’t Record", systemImage: "xmark.circle") { model.recorder.stop(recording.id) }
            default: Button("Delete", systemImage: "trash", role: .destructive) { model.recorder.delete(recording.id) }
            }
        }
        .accessibilityIdentifier("recording.\(recording.id.uuidString)")
        .accessibilityValue(recording.status.rawValue)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: recording.title).font(.system(size: 22, weight: .semibold)).lineLimit(1)
            Text(verbatim: detail).font(.system(size: 19)).lineLimit(1)
                .foregroundStyle(recording.status == .failed || recording.status == .missed ? TVTheme.warning : TVTheme.text.opacity(0.6))
        }
        .frame(width: 340, alignment: .leading)
        .padding(.top, -6)
    }

    private var detail: String {
        let time = recording.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        switch recording.status {
        case .recording: return String(localized: "\(recording.channelName) · until \(recording.recordEnd.formatted(.dateTime.hour().minute()))")
        case .scheduled: return "\(time) · \(recording.channelName)"
        case .missed: return String(localized: "Missed · Fernsy was not open")
        case .failed: return String(localized: "Failed · \(recording.error ?? "")")
        default:
            let minutes = Int(recording.recordEnd.timeIntervalSince(recording.recordStart) / 60)
            return String(localized: "\(time) · \(minutes) min")
        }
    }
}

/// The card's picture: a colour from the channel, its logo, the state's badge and progress.
private struct CardImage: View {
    @EnvironmentObject private var model: TVModel
    let recording: Recording
    let channel: LiveChannel?

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: Self.colors(recording.channelId), startPoint: .top, endPoint: .bottom)
            if let channel {
                ChannelLogo(channel: channel, radius: 9).frame(width: 84, height: 52).padding(12)
            }
            badge.frame(maxWidth: .infinity, alignment: .topTrailing).padding(12)
            if let share = progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule().fill(recording.status == .recording ? Color(hex: 0xFF4D45) : .white).frame(width: geo.size.width * share)
                    }
                }
                .frame(height: 6)
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: 340, height: 191)
        .opacity(recording.status == .failed && recording.fileName == nil || recording.status == .missed ? 0.6 : 1)
    }

    private var progress: Double? {
        if recording.status == .recording {
            let total = recording.recordEnd.timeIntervalSince(recording.recordStart)
            return total > 0 ? min(1, Date().timeIntervalSince(recording.recordStart) / total) : nil
        }
        let share = model.watchedShare(recording)
        return share > 0 ? share : nil
    }

    @ViewBuilder private var badge: some View {
        switch recording.status {
        case .recording: Badge(text: "● REC", background: TVTheme.live, foreground: .white)
        case .scheduled: Badge(text: "Scheduled", background: Color(hex: 0x0F0E12, opacity: 0.65), foreground: Color(hex: 0xFF8A80))
        case .failed: Badge(text: "⚠︎ Error", background: TVTheme.warning, foreground: Color(hex: 0x1A1300))
        case .missed: Badge(text: "Missed", background: TVTheme.warning, foreground: Color(hex: 0x1A1300))
        default: EmptyView()
        }
    }

    /// A stable colour per channel, like the design's artwork.
    static func colors(_ channelId: Int) -> [Color] {
        let hue = Double((channelId * 47) % 360) / 360
        return [Color(hue: hue, saturation: 0.45, brightness: 0.62), Color(hue: hue, saturation: 0.5, brightness: 0.22)]
    }
}

private struct Badge: View {
    let text: LocalizedStringKey
    let background: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(background, in: .capsule)
            .foregroundStyle(foreground)
    }
}

/// A recording full screen: Left/Right 10 s, Play/Pause, a click shows the timeline, Back stops
/// and keeps the position.
struct RecordingPlayerScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var showsOverlay = true
    @State private var lastInput = Date()
    /// The player takes focus, so Back and the remote reach it, not the card below the cover.
    @FocusState private var focused: Bool
    /// The file failed to play: the status layer's card takes focus (tvos-player-status).
    @State private var failed = false

    // The status layer sits beside the player, not inside it: under the player's remote
    // handlers (move, tap, exit) focus could not move between the failure card's buttons.
    var body: some View {
        ZStack {
            player
            status
        }
    }

    @ViewBuilder private var status: some View {
        if let recording = model.playingRecording {
            PlayerStatusLayer(engine: model.engine, title: recording.title,
                              retry: { model.retryPlayback() }, close: { model.stop() })
        }
    }

    private var player: some View {
        ZStack(alignment: .bottomLeading) {
            TVVideoSurface(engine: model.engine).ignoresSafeArea()
            StreamInfoPanel(engine: model.engine)
            if showsOverlay, let recording = model.playingRecording {
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 420).frame(maxHeight: .infinity, alignment: .bottom).ignoresSafeArea()
                RecordingOverlay(recording: recording, progress: model.engine.progress)
            }
            RecordingPlayerState(engine: model.engine)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .focusable(!failed)
        .focused($focused)
        .onAppear { focused = true }
        .onReceive(model.engine.$status) { status in
            let now = if case .failed = status { true } else { false }
            if failed != now { failed = now }
        }
        .onChange(of: failed) { _, value in if !value { focused = true } }
        .onChange(of: focused) { _, value in AppLog.detail(.player, "recording player focused: \(value)") }
        .onPlayPauseCommand { model.togglePause(); touch() }
        .onMoveCommand(perform: failed ? nil : { direction in
            AppLog.detail(.player, "remote \(direction) in the recording player")
            switch direction {
            case .left: model.skip(by: -10)
            case .right: model.skip(by: 10)
            default: break
            }
            touch()
        })
        .onTapGesture { if !failed { showsOverlay.toggle(); touch() } }
        .onExitCommand {
            AppLog.detail(.player, "remote back in the recording player")
            model.stop()
        }
        .task(id: lastInput) {
            guard (try? await Task.sleep(for: .seconds(6))) != nil else { return }
            showsOverlay = false
        }
    }

    private func touch() {
        showsOverlay = true
        lastInput = Date()
    }
}

private struct RecordingOverlay: View {
    let recording: Recording
    @ObservedObject var progress: PlaybackProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: "\(recording.channelName) · \(TimeSpan.of(recording.start, recording.end))").font(.system(size: 22)).opacity(0.75)
            Text(verbatim: recording.title).font(.system(size: 44, weight: .bold)).lineLimit(1)
            GeometryReader { geo in
                let share = progress.duration > 0 ? min(1, progress.position / progress.duration) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28))
                    Capsule().fill(.white).frame(width: geo.size.width * share)
                }
            }
            .frame(height: 10)
            HStack {
                Text(Duration.seconds(progress.position).formatted(.time(pattern: .hourMinuteSecond)))
                Spacer()
                Text(verbatim: "−" + Duration.seconds(max(0, progress.duration - progress.position)).formatted(.time(pattern: .hourMinuteSecond)))
            }
            .font(.system(size: 21).monospacedDigit()).opacity(0.7)
        }
        .padding(.horizontal, 90)
        .padding(.bottom, 70)
    }
}

private struct RecordingPlayerState: View {
    @ObservedObject var engine: PlayerEngine

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("player.state")
            .accessibilityValue(engine.status == .playing ? "playing" : engine.status == .paused ? "paused" : "other")
    }
}
