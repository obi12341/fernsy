import Combine
import FernsyCore
import FernsyPlayer
import SwiftUI

/// Films, episodes and Jellyfin items full screen: Left/Right 10 s, Play/Pause, a click shows
/// the timeline, Up the audio and subtitle choice, Back stops (positions are kept or reported).
/// When an episode ends and a next one exists, a countdown starts it, as on the Mac.
struct VODPlayerScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var showsOverlay = true
    @State private var lastInput = Date()
    @State private var tracks: TrackKind?
    @State private var countdown: Int?
    @FocusState private var focused: Bool

    enum TrackKind { case audio, subtitles }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVVideoSurface(engine: model.engine).ignoresSafeArea()
            StreamInfoPanel(engine: model.engine)
            if let item = model.playingVOD {
                if showsOverlay || countdown != nil {
                    LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top)
                        .frame(height: 440).frame(maxHeight: .infinity, alignment: .bottom).ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                if let countdown, let next = model.nextAfterPlaying {
                    NextEpisodeCard(next: next, seconds: countdown) { playNext() } cancel: { cancelNext() }
                        .padding(.trailing, 90).padding(.bottom, 70)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else if let tracks {
                    VODTrackPanel(kind: tracks, engine: model.engine) { self.tracks = nil; focused = true }
                } else if showsOverlay {
                    VODOverlay(item: item, progress: model.engine.progress)
                }
            }
            VODPlayerState(engine: model.engine)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .focusable(tracks == nil && countdown == nil)
        .focused($focused)
        .onAppear { focused = true }
        .onPlayPauseCommand { model.togglePause(); touch() }
        .onMoveCommand { direction in
            switch direction {
            case .left: model.skip(by: -10)
            case .right: model.skip(by: 10)
            case .up: tracks = .audio
            case .down: tracks = .subtitles
            default: break
            }
            touch()
        }
        .onTapGesture { showsOverlay.toggle(); touch() }
        .onExitCommand {
            if tracks != nil { tracks = nil; focused = true } else { model.stop() }
        }
        .task(id: lastInput) {
            guard (try? await Task.sleep(for: .seconds(6))) != nil else { return }
            showsOverlay = false
        }
        .onReceive(model.engine.$status) { status in
            // An IPTV episode at its end: count down to the next one. (onChange of
            // model.engine.status never fired: the screen observes the model, not its engine.)
            if status == .ended, case .episode = model.playingVOD, model.nextAfterPlaying != nil, countdown == nil { countdown = 10 }
        }
        .onReceive(model.jellyfinPlayback?.$autoplayAt.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { date in
            countdown = date.map { max(0, Int($0.timeIntervalSinceNow.rounded())) }
        }
        .task(id: countdown) {
            guard let value = countdown else { return }
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            if value <= 1 { playNext() } else { countdown = value - 1 }
        }
    }

    private func touch() {
        showsOverlay = true
        lastInput = Date()
    }

    private func playNext() {
        guard let next = model.nextAfterPlaying else { countdown = nil; return }
        countdown = nil
        model.play(next, fromStart: true)
    }

    private func cancelNext() {
        countdown = nil
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

/// "Next Episode in 7 s" with Play Now and Cancel.
private struct NextEpisodeCard: View {
    let next: VODItem
    let seconds: Int
    let play: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Next episode in \(seconds) s").font(.system(size: 22, weight: .semibold)).opacity(0.75)
                .accessibilityIdentifier("vod.countdown")
            Text(verbatim: next.subtitle ?? next.title).font(.system(size: 30, weight: .bold)).lineLimit(1)
            HStack(spacing: 18) {
                Button("Play Now", action: play).buttonStyle(TVPillStyle())
                Button("Cancel", action: cancel).buttonStyle(TVPillStyle(prominent: false))
            }
            .focusSection()
        }
        .padding(30)
        .frame(width: 640, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
    }
}

private struct VODTrackPanel: View {
    let kind: VODPlayerScreen.TrackKind
    @ObservedObject var engine: PlayerEngine
    let done: () -> Void

    var body: some View {
        let media = engine.media
        let list = kind == .audio ? media?.audioTracks ?? [] : media?.subtitleTracks ?? []
        let selected = kind == .audio ? media?.selectedAudio : media?.selectedSubtitle
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .audio ? "Audio" : "Subtitles").font(.system(size: 34, weight: .bold))
            if kind == .subtitles { row(Text("Off"), on: selected == nil) { engine.selectSubtitle(nil) } }
            ForEach(list, id: \.id) { track in
                row(Text(verbatim: track.title), on: selected == track.id) {
                    if kind == .audio { engine.selectAudio(track) } else { engine.selectSubtitle(track) }
                }
            }
        }
        .padding(40)
        .frame(width: 620, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
        .padding(.leading, 90).padding(.bottom, 80)
        .focusSection()
    }

    private func row(_ title: Text, on: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); done() } label: {
            HStack { title; Spacer(); if on { Image(systemName: "checkmark") } }
                .font(.system(size: 24, weight: .medium)).padding(.horizontal, 24).frame(height: 64)
        }
        .buttonStyle(TVTileStyle(rest: .white.opacity(0.08), radius: 16, scale: 1.03))
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
