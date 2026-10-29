import FernsyCore
import FernsyPlayer
import SwiftUI

/// The full-screen player (design screens `player` and `zap`). Without the overlay, a click or
/// swipe shows it; Left/Right go 10 s back or forward, Down opens the channel strip, Play/Pause
/// pauses, Back closes. With the overlay, a click goes back to live when behind it, Up reaches
/// the tabs Info, Subtitles, Audio and Channels.
struct PlayerScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var mode: Mode = .hidden
    @State private var lastInput = Date()
    /// The player takes focus, so Back and the remote reach it, not the row below the cover.
    @FocusState private var focused: Bool
    /// The stream failed: the status layer's card takes focus (tvos-player-status design 5).
    @State private var failed = false

    enum Mode: Equatable {
        case hidden, info
        case tabs(Tab)
        case tracks(Tab)
        case strip
    }

    enum Tab: Int, CaseIterable {
        case info, subtitles, audio, channels

        var title: LocalizedStringKey {
            switch self {
            case .info: "Info"
            case .subtitles: "Subtitles"
            case .audio: "Audio"
            case .channels: "Channels"
            }
        }
    }

    // The status layer sits beside the player, not inside it: under the player's remote
    // handlers (move, tap, exit) focus could not move between the failure card's buttons.
    var body: some View {
        ZStack {
            player
            status
        }
    }

    @ViewBuilder private var status: some View {
        if let channel = model.playing {
            PlayerStatusLayer(engine: model.engine, title: channel.displayName, channel: channel,
                              canTakeFocus: mode == .hidden || mode == .info,
                              retry: { model.retryPlayback() },
                              next: { mode = .hidden; Task { await model.zapToNext() } },
                              close: { model.stop() })
        }
    }

    private var player: some View {
        ZStack(alignment: .bottomLeading) {
            TVVideoSurface(engine: model.engine).ignoresSafeArea()
            StreamInfoPanel(engine: model.engine)
            if mode != .hidden {
                LinearGradient(colors: [.black.opacity(mode == .strip ? 0.78 : 0.7), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: mode == .strip ? 560 : 520)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if let channel = model.playing {
                RecordingBadge(channel: channel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 90).padding(.top, 60)
                switch mode {
                case .hidden:
                    EmptyView()
                case .info, .tabs:
                    InfoOverlay(channel: channel, engine: model.engine, progress: model.engine.progress, selectedTab: selectedTab)
                case .tracks(let tab):
                    TrackPanel(tab: tab, engine: model.engine) { mode = .info }
                case .strip:
                    ChannelStrip { channel in
                        mode = .hidden
                        Task { await model.zap(to: channel) }
                    }
                }
            }
            PlayerState(engine: model.engine)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        // The UI tests wait for the player's focus before pressing (tvos-uitest-shards); tvOS does
        // not report the focus of this container to them, so its value does.
        .accessibilityIdentifier("player.surface")
        .accessibilityValue(focused ? "focused" : "unfocused")
        .focusable(mode != .strip && !isTracks && !(failed && (mode == .hidden || mode == .info)))
        .focused($focused)
        .onAppear { focused = true }
        .onReceive(model.engine.$status) { status in
            let now = if case .failed = status { true } else { false }
            if failed != now { failed = now }
        }
        .onChange(of: failed) { _, value in if !value { focused = true } }
        .onChange(of: mode) { _, value in if value == .hidden || value == .info { focused = true } }
        .onPlayPauseCommand { model.togglePause(); touch() }
        .onMoveCommand(perform: failed ? nil : { move($0) })
        .onTapGesture { if !failed { click() } }
        .onExitCommand { back() }
        #if DEBUG
        // IPTV_PLAYERMODE=info|strip: the player opens with that overlay (screenshots without a remote).
        .onAppear {
            switch ProcessInfo.processInfo.environment["IPTV_PLAYERMODE"] {
            case "info": mode = .info
            case "strip": mode = .strip
            default: break
            }
        }
        #endif
        .task(id: lastInput) {
            // The overlay hides after a few seconds without input (not while choosing).
            // New input cancels the sleep; then the overlay stays (try? alone would hide it at once).
            guard (try? await Task.sleep(for: .seconds(6))) != nil else { return }
            if mode == .info { mode = .hidden }
        }
    }

    private var isTracks: Bool { if case .tracks = mode { true } else { false } }

    private var selectedTab: Tab? { if case .tabs(let tab) = mode { tab } else { nil } }

    private func touch() { lastInput = Date() }

    private func click() {
        touch()
        switch mode {
        case .hidden: mode = .info
        case .info: if !model.engine.progress.followsLive { model.goLive() } else { mode = .hidden }
        case .tabs(let tab):
            switch tab {
            case .info: mode = .info
            case .subtitles, .audio: mode = .tracks(tab)
            case .channels: mode = .strip
            }
        default: break
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        touch()
        AppLog.detail(.player, "remote \(direction) in \(mode)")
        switch (mode, direction) {
        case (.hidden, .left), (.info, .left): model.skip(by: -10); mode = .info
        case (.hidden, .right), (.info, .right): model.skip(by: 10); mode = .info
        case (.hidden, .down), (.info, .down): mode = .strip
        case (.hidden, .up): mode = .info
        case (.info, .up): mode = .tabs(.info)
        case (.tabs(let tab), .left): mode = .tabs(Tab(rawValue: max(0, tab.rawValue - 1)) ?? tab)
        case (.tabs(let tab), .right): mode = .tabs(Tab(rawValue: min(Tab.allCases.count - 1, tab.rawValue + 1)) ?? tab)
        case (.tabs, .down): mode = .info
        default: break
        }
    }

    private func back() {
        touch()
        AppLog.detail(.player, "remote back in \(mode)")
        switch mode {
        case .hidden: model.stop()
        case .info: mode = .hidden
        case .tabs, .tracks, .strip: mode = .info
        }
    }
}

/// The player's state for the UI tests: always present, independent of the overlay and the language.
private struct PlayerState: View {
    @ObservedObject var engine: PlayerEngine

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("player.state")
            .accessibilityValue(value)
    }

    private var value: String {
        switch engine.status {
        case .playing: "playing"
        case .paused: "paused"
        case .buffering, .loading: "loading"
        case .failed: "failed"
        case .ended: "ended"
        case .idle: "idle"
        }
    }
}

/// "● Recording · until 22:55" while the playing channel is recorded.
private struct RecordingBadge: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel

    var body: some View {
        if let recording = model.activeRecording(on: channel) {
            HStack(spacing: 10) {
                Circle().fill(.white).frame(width: 12, height: 12)
                Text("Recording · until \(recording.recordEnd.formatted(.dateTime.hour().minute()))")
            }
            .font(.system(size: 20, weight: .bold))
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(TVTheme.live, in: .capsule)
            .accessibilityIdentifier("player.recording")
        }
    }
}

// MARK: Info overlay

private struct InfoOverlay: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var progress: PlaybackProgress
    let selectedTab: PlayerScreen.Tab?

    var body: some View {
        let playhead = progress.wallClock ?? Date()
        let show = model.currentShow(on: channel, at: playhead)
        let next = model.nextShows(on: channel, count: 1, at: playhead).first
        VStack(alignment: .leading, spacing: 26) {
            TabPills(selected: selectedTab, highlighted: selectedTab ?? .info)
            HStack(alignment: .bottom, spacing: 24) {
                ChannelLogo(channel: channel).frame(width: 122, height: 75)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: show.map { "\(channel.displayName) · \(TimeSpan.of($0))" } ?? channel.displayName)
                        .font(.system(size: 22)).opacity(0.75)
                    Text(verbatim: show?.title ?? channel.displayName).font(.system(size: 44, weight: .bold)).lineLimit(1)
                }
                Spacer()
                if let next {
                    Text("Next \(next.start.formatted(.dateTime.hour().minute())) \(next.title)")
                        .font(.system(size: 22)).opacity(0.75).lineLimit(1)
                }
            }
            Timeline(channel: channel, show: show, engine: engine, progress: progress)
            HStack {
                if let start = engine.wallTime(of: progress.liveStart), engine.isTimeshift {
                    Text("Buffer since \(start.formatted(.dateTime.hour().minute()))")
                }
                Spacer()
                HStack(spacing: 16) {
                    if !progress.followsLive {
                        Text(verbatim: "−" + Duration.seconds(progress.behindLive).formatted(.time(pattern: progress.behindLive >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                            .fontWeight(.bold)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(.white.opacity(0.2), in: .capsule)
                            .accessibilityIdentifier("player.behind")
                        Text("Click: Back to Live")
                    }
                    Text("Swipe down: Channels")
                }
            }
            .font(.system(size: 21).monospacedDigit())
            .opacity(0.7)
            .padding(.top, -14)
        }
        .padding(.horizontal, 90)
        .padding(.bottom, 70)
    }
}

private struct TabPills: View {
    let selected: PlayerScreen.Tab?
    let highlighted: PlayerScreen.Tab

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PlayerScreen.Tab.allCases, id: \.self) { tab in
                let on = tab == highlighted
                Text(tab.title)
                    .font(.system(size: 23, weight: .semibold))
                    .padding(.horizontal, 24)
                    .frame(height: 50)
                    .foregroundStyle(on ? TVTheme.focusedText : .white)
                    .background(on ? Color.white.opacity(0.9) : Color.white.opacity(0.14), in: .capsule)
                    .scaleEffect(selected == tab ? 1.08 : 1)
                    .animation(.easeOut(duration: 0.15), value: selected)
            }
        }
    }
}

/// The timeshift buffer from its start to the show's end (or now): what is buffered, the
/// playhead with its clock time, the show's start and, while recorded, a red mark at the live point.
private struct Timeline: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    let show: EPGEntry?
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var progress: PlaybackProgress

    var body: some View {
        let now = Date()
        let start = engine.wallTime(of: progress.liveStart) ?? now
        let end = max(show?.end ?? now, now.addingTimeInterval(60))
        let total = max(1, end.timeIntervalSince(start))
        let playhead = progress.wallClock ?? now
        let at = { (date: Date) in CGFloat(min(1, max(0, date.timeIntervalSince(start) / total))) }
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(.white.opacity(0.28)).frame(height: 10).offset(y: 20)
                Capsule().fill(.white.opacity(0.55)).frame(width: w * at(now), height: 10).offset(y: 20)
                Capsule().fill(.white).frame(width: w * at(playhead), height: 10).offset(y: 20)
                if let show, show.start > start {
                    Rectangle().fill(.white.opacity(0.7)).frame(width: 3, height: 22).offset(x: w * at(show.start), y: 14)
                }
                if model.activeRecording(on: channel) != nil {
                    Circle().fill(TVTheme.live).frame(width: 14, height: 14).offset(x: w * at(now) - 7, y: 18)
                }
                RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 4, height: 38)
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .offset(x: w * at(playhead) - 2, y: 6)
                Text(playhead, format: .dateTime.hour().minute())
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .frame(width: 120)
                    .offset(x: w * at(playhead) - 60, y: -36)
            }
        }
        .frame(height: 48)
    }
}

// MARK: Tracks

/// Subtitles or audio tracks of the playing channel, to choose one (design: Untertitel, Ton).
private struct TrackPanel: View {
    let tab: PlayerScreen.Tab
    @ObservedObject var engine: PlayerEngine
    let done: () -> Void

    var body: some View {
        let media = engine.media
        let tracks = tab == .audio ? media?.audioTracks ?? [] : media?.subtitleTracks ?? []
        let selected = tab == .audio ? media?.selectedAudio : media?.selectedSubtitle
        VStack(alignment: .leading, spacing: 16) {
            Text(tab.title).font(.system(size: 34, weight: .bold))
            if tab == .subtitles {
                trackButton(title: Text("Off"), on: selected == nil) { engine.selectSubtitle(nil) }
            }
            ForEach(tracks, id: \.id) { track in
                trackButton(title: Text(verbatim: track.title), on: selected == track.id) {
                    if tab == .audio { engine.selectAudio(track) } else { engine.selectSubtitle(track) }
                }
            }
            if tracks.isEmpty && tab == .audio {
                Text("This channel has one audio track.").font(.system(size: 22)).opacity(0.7)
            }
        }
        .padding(40)
        .frame(width: 620, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
        .padding(.leading, 90).padding(.bottom, 80)
        .focusSection()
    }

    private func trackButton(title: Text, on: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); done() } label: {
            HStack {
                title
                Spacer()
                if on { Image(systemName: "checkmark") }
            }
            .font(.system(size: 24, weight: .medium))
            .padding(.horizontal, 24)
            .frame(height: 64)
        }
        .buttonStyle(TVTileStyle(rest: .white.opacity(0.08), radius: 16, scale: 1.03))
    }
}

// MARK: Channel strip

/// The channels of the zap source with now, progress and next (design screen `zap`).
private struct ChannelStrip: View {
    @EnvironmentObject private var model: TVModel
    let tune: (LiveChannel) -> Void
    @FocusState private var focused: Int?

    var body: some View {
        let channels = model.zapChannels
        VStack(alignment: .leading, spacing: 30) {
            TabPills(selected: nil, highlighted: .channels)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: 30) {
                    ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                        Button { tune(channel) } label: {
                            StripCard(channel: channel, number: number(of: channel), guide: model.guide.guide(channel.id), playing: index == 0)
                        }
                        .buttonStyle(StripStyle(playing: index == 0))
                        .focused($focused, equals: channel.id)
                        .accessibilityIdentifier("strip.\(channel.id)")
                    }
                }
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
            .frame(height: 290)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.leading, 90)
        .padding(.bottom, 50)
        .onAppear { focused = channels.dropFirst().first?.id ?? channels.first?.id }
    }

    /// The channel's place in its source, as in Live TV's rows.
    private func number(of channel: LiveChannel) -> Int {
        (model.channels(for: model.zapSource).firstIndex { $0.id == channel.id } ?? 0) + 1
    }
}

private struct StripStyle: ButtonStyle {
    let playing: Bool

    func makeBody(configuration: Configuration) -> some View {
        Card(configuration: configuration, playing: playing)
    }

    private struct Card: View {
        let configuration: Configuration
        let playing: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? TVTheme.focusedText : TVTheme.text)
                .background(focused ? TVTheme.focused : Color(hex: 0x282630, opacity: 0.6), in: .rect(cornerRadius: 24))
                .overlay {
                    if !focused {
                        RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(playing ? 0.5 : 0.1), lineWidth: playing ? 2 : 1)
                    }
                }
                .scaleEffect(focused ? 1.08 : 1, anchor: .bottom)
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 25, y: 26)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

private struct StripCard: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    let number: Int
    @ObservedObject var guide: ChannelGuide
    let playing: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        let show = model.currentShow(on: channel)
        let next = model.nextShows(on: channel, count: 1).first
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ChannelLogo(channel: channel, radius: 11).frame(width: 104, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playing ? "\(number) · On now" : "\(number)").font(.system(size: 18).monospacedDigit()).opacity(0.6)
                    Text(verbatim: channel.displayName).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: show?.title ?? "").font(.system(size: 22, weight: .semibold)).lineLimit(1)
                if let show { ShowProgress(show: show, focused: focused).frame(height: 5) }
                Text(verbatim: next.map { String(localized: "Next \($0.start.formatted(.dateTime.hour().minute())) \($0.title)") } ?? "")
                    .font(.system(size: 19)).opacity(0.6).lineLimit(1)
            }
        }
        .padding(22)
        .frame(width: 360, alignment: .leading)
        .task { await model.loadGuide(for: channel) }
    }
}
