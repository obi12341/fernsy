import AVKit
import Combine
import FernsyCore
import FernsyPlayer
import SwiftUI

/// The full-screen player for live channels and on-demand items (ios-app "Live player",
/// "On-demand playback"): landscape on iPhone, controls on a tap that hide after a few seconds,
/// swipe down closes, sideways swipes on a live picture zap.
struct PlayerView: View {
    @EnvironmentObject private var model: TVModel
    @StateObject private var pip = PictureInPicture.shared
    @State private var showsControls = true
    @State private var lastInput = Date()
    @State private var showsChannels = false
    @State private var countdown: Int?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVVideoSurface(engine: model.engine)
                .ignoresSafeArea()
                .offset(y: max(0, dragOffset))
            StreamInfoPanel(engine: model.engine)
            // A tap on the picture shows or hides the controls. A layer of its own under them:
            // a tap gesture on the whole player took the taps of the buttons in the top bar.
            Color.clear
                .contentShape(.rect)
                .ignoresSafeArea()
                .onTapGesture { showsControls.toggle(); touch() }
            if showsControls || countdown != nil {
                LinearGradient(colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if let countdown, let next = model.nextAfterPlaying {
                NextEpisodeCard(next: next, seconds: countdown, play: playNext, cancel: cancelNext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(24)
            } else if showsControls && !showsChannels {
                controls
            }
            status
            PlayerState(engine: model.engine)
        }
        .foregroundStyle(.white)
        .statusBarHidden(!showsControls)
        .persistentSystemOverlays(.hidden)
        // Simultaneous: a swipe that starts on a button (play/pause in the middle) still counts.
        .simultaneousGesture(swipes)
        .task(id: lastInput) {
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            #if DEBUG
            // IPTV_KEEPCONTROLS=1: the controls stay (screenshots without touch input).
            if ProcessInfo.processInfo.environment["IPTV_KEEPCONTROLS"] == "1" { return }
            #endif
            if !showsChannels { withAnimation { showsControls = false } }
        }
        .onAppear {
            Orientation.landscapeOnPhone(true)
            pip.attach(engine: model.engine)
            #if DEBUG
            // IPTV_PLAYERMODE=channels: the channel list opens with the player (screenshots).
            if ProcessInfo.processInfo.environment["IPTV_PLAYERMODE"] == "channels", model.playing != nil { showsChannels = true }
            #endif
        }
        .onDisappear { if !PlayerPresentation.shared.inPictureInPicture { Orientation.landscapeOnPhone(false) } }
        // The channel list as a panel at the trailing edge: the picture keeps playing beside it
        // (a sheet covers the whole landscape screen).
        .overlay(alignment: .trailing) {
            if showsChannels {
                ChannelListSheet(close: { showsChannels = false }) { channel in
                    showsChannels = false
                    Task { await model.zap(to: channel) }
                }
                .frame(width: 380)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsChannels)
        .onReceive(model.engine.$status) { status in
            // An IPTV episode at its end: count down to the next one (as on Apple TV).
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

    /// The shared status layer is drawn at the Apple TV's sizes; scaled for touch screens.
    @ViewBuilder private var status: some View {
        statusLayer.scaleEffect(UIDevice.current.userInterfaceIdiom == .phone ? 0.6 : 0.8)
    }

    @ViewBuilder private var statusLayer: some View {
        if let channel = model.playing {
            PlayerStatusLayer(engine: model.engine, title: channel.displayName, channel: channel,
                              retry: { model.retryPlayback() },
                              next: { Task { await model.zapToNext() } },
                              close: { model.stop() })
        } else if let item = model.playingVOD {
            PlayerStatusLayer(engine: model.engine, title: item.title, pending: true,
                              retry: { model.retryPlayback() }, close: { model.stop() })
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            TopBar(pip: pip, close: { model.stop() }, channels: model.playing != nil ? { showsChannels = true; touch() } : nil)
            Spacer()
            // Under a failure card the buttons would show through it.
            if !isFailed { CenterButtons(engine: model.engine, touch: touch) }
            Spacer()
            if let channel = model.playing {
                LiveBottomBar(channel: channel, engine: model.engine, progress: model.engine.progress, touch: touch)
            } else if let item = model.playingVOD {
                VODBottomBar(item: item, engine: model.engine, progress: model.engine.progress, touch: touch)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .transition(.opacity)
    }

    /// Down closes the player (the picture follows the finger). Left and right on a live picture
    /// zap to the next or previous channel, only while the controls are hidden: with them shown, a
    /// sideways drag may be meant for the timeline.
    private var swipes: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                if value.translation.height > abs(value.translation.width) { dragOffset = value.translation.height }
            }
            .onEnded { value in
                let dy = value.translation.height, dx = value.translation.width
                defer { withAnimation(.spring) { dragOffset = 0 } }
                if dy > abs(dx), dy > 80 {
                    model.stop()
                } else if abs(dx) > abs(dy), abs(dx) > 80, !showsControls, model.playing != nil {
                    let list = model.zapChannels
                    // zapChannels starts at the playing channel: left is the next, right the previous.
                    guard let target = dx < 0 ? list.dropFirst().first : list.last, target.id != model.playing?.id else { return }
                    Task { await model.zap(to: target) }
                }
            }
    }

    private func touch() { lastInput = Date() }

    private var isFailed: Bool { if case .failed = model.engine.status { true } else { false } }

    private func playNext() {
        guard let next = model.nextAfterPlaying else { countdown = nil; return }
        countdown = nil
        model.play(next, fromStart: true)
    }

    private func cancelNext() {
        countdown = nil
        model.jellyfinPlayback?.cancelAutoplay()
    }
}

// MARK: Controls

private struct TopBar: View {
    @EnvironmentObject private var model: TVModel
    @ObservedObject var pip: PictureInPicture
    let close: () -> Void
    let channels: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Button(action: close) { Image(systemName: "xmark").hitTarget() }
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("player.close")
            title
            Spacer()
            TrackMenu(engine: model.engine)
            if pip.isPossible {
                Button { pip.toggle() } label: { Image(systemName: "pip.enter").hitTarget() }
                    .accessibilityLabel(Text("Picture in Picture"))
                    .accessibilityIdentifier("player.pip")
            }
            AirPlayButton().frame(width: 44, height: 44).clipped()
            if let channels {
                Button(action: channels) { Image(systemName: "list.bullet").hitTarget() }
                    .accessibilityLabel(Text("Channels"))
                    .accessibilityIdentifier("player.channels")
            }
        }
        .font(.title3.weight(.semibold))
        .buttonStyle(.plain)
    }

    @ViewBuilder private var title: some View {
        if let channel = model.playing {
            HStack(spacing: 10) {
                ChannelLogo(channel: channel).frame(width: 52, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: channel.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let show = model.currentShow(on: channel, at: model.engine.progress.wallClock ?? Date()) {
                        Text(verbatim: show.title).font(.caption).opacity(0.75).lineLimit(1)
                    }
                }
            }
        } else if let item = model.playingVOD {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let subtitle = item.subtitle { Text(verbatim: subtitle).font(.caption).opacity(0.75).lineLimit(1) }
            }
        }
    }
}

/// Back 10 s, play/pause, forward 10 s in the middle.
private struct CenterButtons: View {
    @ObservedObject var engine: PlayerEngine
    let touch: () -> Void

    var body: some View {
        HStack(spacing: 56) {
            Button { engine.seek(by: -10); touch() } label: { round(Image(systemName: "gobackward.10"), size: 56) }
                .accessibilityIdentifier("player.back10")
            Button { engine.togglePause(); touch() } label: {
                round(Image(systemName: engine.isPaused ? "play.fill" : "pause.fill").font(.system(size: 34)), size: 76)
            }
            .accessibilityLabel(engine.isPaused ? Text("Play") : Text("Pause"))
            .accessibilityIdentifier("player.playPause")
            Button { engine.seek(by: 10); touch() } label: { round(Image(systemName: "goforward.10"), size: 56) }
                .accessibilityIdentifier("player.forward10")
        }
        .font(.system(size: 26, weight: .semibold))
        .buttonStyle(.plain)
    }

    /// A dark disc behind the symbol: the buttons stay readable over a bright picture.
    private func round(_ symbol: some View, size: CGFloat) -> some View {
        symbol.frame(width: size, height: size).background(.black.opacity(0.45), in: .circle)
    }
}

/// The live timeline across the timeshift buffer, the time behind live and "Live".
private struct LiveBottomBar: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var progress: PlaybackProgress
    let touch: () -> Void
    @State private var dragging: Double?

    var body: some View {
        let start = progress.liveStart, end = max(progress.liveStart + 1, progress.liveEnd)
        VStack(spacing: 6) {
            Slider(value: Binding(get: { dragging ?? (progress.followsLive ? end : progress.position) },
                                  set: { dragging = $0; touch() }),
                   in: start...end) { editing in
                if !editing, let target = dragging {
                    if end - target < 3 { engine.goLive() } else { engine.seek(to: target) }
                    dragging = nil
                }
            }
            .tint(.white)
            .disabled(!engine.isTimeshift)
            .accessibilityIdentifier("player.timeline")
            HStack {
                if let since = engine.wallTime(of: start), engine.isTimeshift {
                    Text("Buffer since \(since.formatted(.dateTime.hour().minute()))")
                }
                Spacer()
                if !progress.followsLive {
                    Text(verbatim: "−" + Duration.seconds(progress.behindLive).formatted(.time(pattern: progress.behindLive >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                        .fontWeight(.bold)
                        .accessibilityIdentifier("player.behind")
                }
                Button { engine.goLive(); touch() } label: {
                    HStack(spacing: 5) {
                        Circle().fill(progress.followsLive ? TVTheme.live : .white.opacity(0.5)).frame(width: 8, height: 8)
                        Text("LIVE").fontWeight(.heavy)
                    }
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(.white.opacity(progress.followsLive ? 0 : 0.2), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(progress.followsLive)
                .accessibilityIdentifier("player.live")
            }
            .font(.caption.monospacedDigit())
        }
    }
}

/// The on-demand timeline with the position and the time left.
private struct VODBottomBar: View {
    let item: VODItem
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var progress: PlaybackProgress
    let touch: () -> Void
    @State private var dragging: Double?

    var body: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(get: { dragging ?? progress.position }, set: { dragging = $0; touch() }),
                   in: 0...max(1, progress.duration)) { editing in
                if !editing, let target = dragging {
                    engine.seek(to: target)
                    dragging = nil
                }
            }
            .tint(.white)
            .accessibilityIdentifier("player.timeline")
            HStack {
                Text(Duration.seconds(dragging ?? progress.position).formatted(.time(pattern: .hourMinuteSecond)))
                Spacer()
                Text(verbatim: "−" + Duration.seconds(max(0, progress.duration - (dragging ?? progress.position))).formatted(.time(pattern: .hourMinuteSecond)))
                    .accessibilityIdentifier("vod.remaining")
            }
            .font(.caption.monospacedDigit())
        }
    }
}

/// Audio and subtitle tracks of what plays, as a menu.
private struct TrackMenu: View {
    @ObservedObject var engine: PlayerEngine

    var body: some View {
        let media = engine.media
        Menu {
            let audio = media?.audioTracks ?? []
            if !audio.isEmpty {
                Section("Audio") {
                    ForEach(audio, id: \.id) { track in
                        Button { engine.selectAudio(track) } label: {
                            if media?.selectedAudio == track.id { Label(track.title, systemImage: "checkmark") } else { Text(verbatim: track.title) }
                        }
                    }
                }
            }
            Section("Subtitles") {
                Button { engine.selectSubtitle(nil) } label: {
                    if media?.selectedSubtitle == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                }
                ForEach(media?.subtitleTracks ?? [], id: \.id) { track in
                    Button { engine.selectSubtitle(track) } label: {
                        if media?.selectedSubtitle == track.id { Label(track.title, systemImage: "checkmark") } else { Text(verbatim: track.title) }
                    }
                }
            }
        } label: {
            Image(systemName: media?.selectedSubtitle != nil ? "captions.bubble.fill" : "captions.bubble").hitTarget()
        }
        .accessibilityLabel(Text("Audio and Subtitles"))
        .accessibilityIdentifier("player.tracks")
    }
}

/// The system's AirPlay picker (ios-app design 6).
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(TVTheme.accentLight)
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// "Next Episode in 7 s" with Play Now and Cancel.
private struct NextEpisodeCard: View {
    let next: VODItem
    let seconds: Int
    let play: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next episode in \(seconds) s").font(.subheadline.weight(.semibold)).opacity(0.75)
                .accessibilityIdentifier("vod.countdown")
            Text(verbatim: next.subtitle ?? next.title).font(.headline).lineLimit(1)
            HStack(spacing: 12) {
                Button("Play Now", action: play).buttonStyle(.borderedProminent)
                Button("Cancel", action: cancel).buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
    }
}

/// The channels of the zap source with now and next; tapping tunes like zapping on the Mac.
private struct ChannelListSheet: View {
    @EnvironmentObject private var model: TVModel
    let close: () -> Void
    let tune: (LiveChannel) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(model.zapChannels.enumerated()), id: \.element.id) { index, channel in
                    Button { tune(channel) } label: {
                        SheetRow(channel: channel, guide: model.guide.guide(channel.id), playing: index == 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("strip.\(channel.id)")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel(Text("Close"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SheetRow: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    @ObservedObject var guide: ChannelGuide
    let playing: Bool

    var body: some View {
        HStack(spacing: 12) {
            ChannelLogo(channel: channel).frame(width: 56, height: 35)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(verbatim: channel.displayName).font(.headline).lineLimit(1)
                    if playing { Text("On now").font(.caption.weight(.bold)).foregroundStyle(TVTheme.accentLight) }
                }
                if let show = model.currentShow(on: channel) {
                    HStack {
                        Text(verbatim: show.title).lineLimit(1)
                        Spacer()
                        ShowProgress(show: show).frame(width: 40, height: 4)
                    }
                    .font(.subheadline).foregroundStyle(TVTheme.secondary)
                }
                if let next = model.nextShows(on: channel, count: 1).first {
                    Text("Next \(next.start.formatted(.dateTime.hour().minute())) \(next.title)")
                        .font(.caption).foregroundStyle(TVTheme.tertiary).lineLimit(1)
                }
            }
        }
        .contentShape(.rect)
        .task { await model.loadGuide(for: channel) }
    }
}

/// The player's state for UI tests: always present, independent of the controls and language.
private struct PlayerState: View {
    @ObservedObject var engine: PlayerEngine

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("player.state")
            .accessibilityValue(value)
            .allowsHitTesting(false)
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

/// The player turns an iPhone to landscape while it shows (ios-app design 4).
@MainActor
enum Orientation {
    static func landscapeOnPhone(_ on: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        AppDelegateOrientation.mask = on ? .landscape : .allButUpsideDown
        // The allowed orientations first (on the top controller, the player while it shows),
        // then the turn: asked the other way round, the old mask refuses it.
        var top = scene.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: on ? .landscape : held)) { error in
            AppLog.warning(.player, "orientation not changed: \(error.localizedDescription)")
        }
    }
}

extension Orientation {
    /// How the iPhone is held, for the screens after the player; flat or unknown is portrait.
    /// (The device's landscape left is the interface's landscape right.)
    static var held: UIInterfaceOrientationMask {
        switch UIDevice.current.orientation {
        case .landscapeLeft: .landscapeRight
        case .landscapeRight: .landscapeLeft
        default: .portrait
        }
    }
}

/// The orientations the app allows right now (read by the app delegate).
@MainActor
enum AppDelegateOrientation {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown
}

private extension View {
    /// A 44-point square that takes the touch, whatever the symbol's size (Apple's minimum target).
    func hitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
    }
}
