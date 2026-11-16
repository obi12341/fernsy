import Combine
import FernsyCore
import FernsyPlayer
import SwiftUI

/// Films, episodes and Jellyfin items full screen: Left/Right 10 s, Play/Pause, a click shows
/// the timeline, Up the audio and subtitle choice, Back closes the panel, the countdown or the
/// timeline first and stops only with none showing (positions are kept or reported).
/// When an episode ends and a next one exists, a countdown starts it, as on the Mac; Jellyfin
/// episodes show it at their credits and offer to skip intros and recaps (Select skips).
struct VODPlayerScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var showsOverlay = true
    @State private var lastInput = Date()
    @State private var tracks: TrackKind?
    /// An IPTV episode ended: when the next one starts.
    @State private var iptvNextAt: Date?
    @FocusState private var focused: Bool
    /// The item failed: the status layer's card takes focus (tvos-player-status design 5).
    @State private var failed = false

    enum TrackKind { case audio, subtitles }

    // The status layer sits beside the player, not inside it: under the player's remote
    // handlers (move, tap, exit) focus could not move between the failure card's buttons.
    var body: some View {
        ZStack {
            player
            status
        }
    }

    @ViewBuilder private var status: some View {
        if let item = model.playingVOD {
            // Pending: a Jellyfin item resolves its stream before the engine loads (design 2).
            PlayerStatusLayer(engine: model.engine, title: item.title, pending: true,
                              canTakeFocus: tracks == nil && !cardShows,
                              retry: { model.retryPlayback() }, close: { model.stop() })
        }
    }

    private var player: some View {
        ZStack(alignment: .bottomLeading) {
            TVVideoSurface(engine: model.engine).ignoresSafeArea()
            StreamInfoPanel(engine: model.engine)
            if let item = model.playingVOD {
                if showsOverlay || cardShows {
                    LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top)
                        .frame(height: 440).frame(maxHeight: .infinity, alignment: .bottom).ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                SubtitleOverlay(engine: model.engine, fontSize: TVSubtitles.fontSize,
                                bottomInset: showsOverlay && tracks == nil && !cardShows ? TVSubtitles.raisedInset : TVSubtitles.bottomInset,
                                sideInset: TVSubtitles.sideInset)
                if let content = upNext {
                    UpNextCard(content: content) { playNext() } dismiss: { cancelNext() }
                        .padding(.trailing, 90).padding(.bottom, 70)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else if let tracks {
                    TrackPanel(audio: tracks == .audio, engine: model.engine) { self.tracks = nil; focused = true }
                } else if showsOverlay {
                    VODOverlay(item: item, progress: model.engine.progress)
                }
            }
            if !cardShows, tracks == nil {
                SkipSegmentPill(skip: jellyfinSkip?.activeSkip, notice: jellyfinSkip?.skippedNotice) { skipSegment() }
                    .padding(.trailing, 90).padding(.bottom, showsOverlay ? 250 : 70)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            VODPlayerState(engine: model.engine)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        // The UI tests wait for the player's focus before pressing (tvos-uitest-shards); tvOS does
        // not report the focus of this container to them, so its value does.
        .accessibilityIdentifier("player.surface")
        .accessibilityValue(focused ? "focused" : "unfocused")
        .focusable(tracks == nil && !cardShows && !failed)
        .focused($focused)
        .onAppear { focused = true }
        .onReceive(model.engine.$status) { status in
            let now = if case .failed = status { true } else { false }
            if failed != now { failed = now }
        }
        .onChange(of: failed) { _, value in if !value { focused = true } }
        .onPlayPauseCommand { model.togglePause(); touch() }
        .onMoveCommand(perform: failed ? nil : { direction in
            // The track panel and the countdown card sit inside the player and move focus
            // themselves: their presses reach this handler too (Up in the subtitle panel opened
            // the audio panel, Left and Right skipped).
            guard tracks == nil, !cardShows else { return }
            switch direction {
            case .left: model.skip(by: -10)
            case .right: model.skip(by: 10)
            case .up: tracks = .audio
            case .down: tracks = .subtitles
            default: break
            }
            touch()
        })
        .onTapGesture {
            guard !failed else { return }
            // While Skip Intro / Skip Recap shows, Select skips (it is no focus target).
            if jellyfinSkip?.activeSkip != nil { skipSegment() } else { showsOverlay.toggle() }
            touch()
        }
        .onExitCommand { back() }
        .task(id: lastInput) {
            guard (try? await Task.sleep(for: .seconds(6))) != nil else { return }
            showsOverlay = false
        }
        .onReceive(model.engine.$status) { status in
            // An IPTV episode at its end: count down to the next one. (onChange of
            // model.engine.status never fired: the screen observes the model, not its engine.)
            if status == .ended, case .episode = model.playingVOD, model.nextAfterPlaying != nil, iptvNextAt == nil {
                iptvNextAt = Date().addingTimeInterval(JellyfinPlayback.autoplayDelay)
            }
        }
        .task(id: iptvNextAt) {
            guard let at = iptvNextAt else { return }
            guard (try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow)))) != nil else { return }
            playNext()
        }
    }

    /// The Jellyfin playback while a Jellyfin item plays (its skip button and note).
    private var jellyfinSkip: JellyfinPlayback? {
        if case .jellyfin? = model.playingVOD { model.jellyfinPlayback } else { nil }
    }

    /// The next-episode card: Jellyfin's from its playback, an IPTV episode's after its end.
    private var upNext: UpNextContent? {
        if case .jellyfin? = model.playingVOD {
            guard let playback = model.jellyfinPlayback, let card = playback.card, let next = playback.nextEpisode else { return nil }
            return UpNextContent(card: card, next: next, deadline: playback.autoplayAt, store: model.jellyfin)
        }
        guard let at = iptvNextAt, let next = model.nextAfterPlaying else { return nil }
        return UpNextContent(line: next.subtitle ?? next.title, deadline: at)
    }

    private var cardShows: Bool { upNext != nil }

    private func touch() {
        showsOverlay = true
        lastInput = Date()
        JellyfinPlayback.noteUserInput()
    }

    private func skipSegment() {
        model.jellyfinPlayback?.skipSegment()
    }

    /// Back closes the topmost layer: the track panel, the next-episode countdown, the timeline;
    /// only with none showing it stops (tvos-back-closes-overlay). Hiding does not touch(), so
    /// the timeline does not come back.
    private func back() {
        if tracks != nil {
            AppLog.detail(.player, "remote back in the track panel")
            tracks = nil
            focused = true
        } else if cardShows {
            AppLog.detail(.player, "remote back in the next-episode card")
            cancelNext()
        } else if showsOverlay {
            AppLog.detail(.player, "remote back in the overlay")
            showsOverlay = false
        } else {
            AppLog.detail(.player, "remote back in hidden")
            model.stop()
        }
    }

    private func playNext() {
        if case .jellyfin? = model.playingVOD, let playback = model.jellyfinPlayback {
            playback.playNext()
            return
        }
        guard let next = model.nextAfterPlaying else { iptvNextAt = nil; return }
        iptvNextAt = nil
        model.play(next, fromStart: true)
    }

    private func cancelNext() {
        iptvNextAt = nil
        model.jellyfinPlayback?.cancelAutoplay()
        focused = true
    }
}

private struct VODOverlay: View {
    let item: VODItem
    @ObservedObject var progress: PlaybackProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let subtitle = item.subtitle { Text(verbatim: subtitle).font(.system(size: 22)).opacity(0.75) }
            Text(verbatim: item.title).font(.system(size: 44, weight: .bold)).lineLimit(1)
            ProgressBar(value: progress.duration > 0 ? progress.position / progress.duration : 0).frame(height: 10)
            HStack {
                Text(Duration.seconds(progress.position).formatted(.time(pattern: .hourMinuteSecond)))
                Spacer()
                Text("Up: Audio · Down: Subtitles")
                Spacer()
                Text(verbatim: "−" + Duration.seconds(max(0, progress.duration - progress.position)).formatted(.time(pattern: .hourMinuteSecond)))
                    .accessibilityIdentifier("vod.remaining")
            }
            .font(.system(size: 21).monospacedDigit()).opacity(0.7)
        }
        .padding(.horizontal, 90)
        .padding(.bottom, 70)
    }
}

private struct VODPlayerState: View {
    @ObservedObject var engine: PlayerEngine

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("player.state")
            .accessibilityValue(engine.status == .playing ? "playing" : engine.status == .paused ? "paused" : engine.status == .ended ? "ended" : "other")
    }
}
