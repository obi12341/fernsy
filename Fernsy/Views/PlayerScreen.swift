import Charts
import Combine
import SwiftUI

struct PlayerScreen: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    @StateObject private var engine = PlayerEngine()

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    /// Sliders being dragged right now: the controls stay up meanwhile (the slider tracks the
    /// mouse, so no hover or move events count as activity).
    @State private var activeDrags = 0
    @State private var showInfo = false
    @State private var pip: PictureInPicture?
    @State private var pipPossible = false
    @State private var pipStage = PictureInPictureStage()
    @State private var epg: [EPGEntry] = []
    @State private var loadedItem: PlayItem?
    @EnvironmentObject private var jellyfin: JellyfinStore
    /// The Jellyfin item playing (direct/transcode, progress reports, next episode).
    @State private var jellyfinPlayback: JellyfinPlayback?
    @State private var isFullScreen = false

    // Zapping: the OSD follows key presses immediately, tuning waits until they stop,
    // so skipping through channels does not open a connection for each one.
    @State private var osd: (channel: LiveChannel, number: Int)?
    @State private var zapTarget: (channel: LiveChannel, number: Int)?
    @State private var zapTask: Task<Void, Never>?
    @State private var osdHideTask: Task<Void, Never>?

    private let resumeTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black

            VideoSurface(engine: engine, onKeyDown: handleKey, onMouseActivity: showControls, onDoubleClick: toggleFullScreen)

            if let text = engine.subtitleText {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: 30, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .shadow(color: .black.opacity(0.8), radius: 6)
                        .padding(.horizontal, 60)
                        .padding(.bottom, controlsVisible ? 150 : 60)
                }
                .allowsHitTesting(false)
            }

            statusOverlay

            if engine.status == .ended, let playback = jellyfinPlayback {
                NextEpisodeOverlay(playback: playback, bottomInset: controlsVisible ? 120 : 32) { next in app.play(jellyfin: next) }
            }

            if let bitmap = engine.subtitleBitmap {
                BitmapSubtitleView(cue: bitmap, videoSize: engine.videoSize)
                    .allowsHitTesting(false)
            }

            if let osd {
                ChannelOSD(channel: osd.channel, number: osd.number, isPending: zapTarget != nil)
                    .id(osd.channel.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 24)
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    .allowsHitTesting(false)
            }

            if let badge = audioBadge {
                AudioStatusBadge(text: badge.text, waiting: badge.waiting)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 24)
                    .padding(.bottom, controlsVisible ? 112 : 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                    .allowsHitTesting(false)
            }

            if controlsVisible, let item = app.nowPlaying {
                PlayerControls(engine: engine, progress: engine.progress, item: item, epg: currentEPG,
                               showInfo: $showInfo, isFullScreen: isFullScreen, showsTitle: osd == nil, onZap: zap, onFullScreen: toggleFullScreen,
                               onActivity: showControls,
                               isRecording: liveChannelID.map { recorder.active(on: $0) != nil },
                               onRecord: toggleRecording, onPickAudio: { pick(audio: $0) }, onPickSubtitle: { pick(subtitle: $0) },
                               onDragging: { dragging in activeDrags = max(0, activeDrags + (dragging ? 1 : -1)) },
                               pipPossible: pipPossible, onPictureInPicture: { pip?.toggle() })
                    .transition(.opacity)
            }

            if showInfo {
                StatsOverlay(stats: engine.stats, status: engine.status, history: engine.bufferHistory)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 50)
                    .padding(.trailing, 20)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 480, minHeight: 270)
        .navigationTitle(app.nowPlaying?.title ?? "Wiedergabe")
        .onAppear {
            setUpPictureInPicture()
            load(app.nowPlaying)
            showControls()
            #if DEBUG
            if ProcessInfo.processInfo.environment["IPTV_SHOWINFO"] != nil { showInfo = true }
            if ProcessInfo.processInfo.environment["IPTV_TESTZAP"] != nil {
                for i in 0..<3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6 + Double(i) * 0.15) {
                        debugLog("[zap] key down #\(i + 1)")
                        zap(1)
                        debugLog("[zap] target \(zapTarget.map { "\($0.channel.id) (#\($0.number))" } ?? "-")")
                    }
                }
            }
            if ProcessInfo.processInfo.environment["IPTV_TESTFS"] != nil {
                // Enter, leave and re-enter full screen to exercise repeated toggling.
                for (delay, label) in [(6.0, "enter"), (10.0, "leave"), (14.0, "re-enter")] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { toggleFullScreen() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.5) {
                        debugLog("[fs] after \(label): fullscreen=\(playerWindow?.styleMask.contains(.fullScreen) ?? false) iconState=\(isFullScreen)")
                    }
                }
            }
            if let spec = ProcessInfo.processInfo.environment["IPTV_TESTPAUSE"]?.split(separator: ":").compactMap({ Double($0) }), spec.count == 2 {
                // IPTV_TESTPAUSE=<at>:<seconds>: pause, then resume (timeshift).
                DispatchQueue.main.asyncAfter(deadline: .now() + spec[0]) { debugLog("[test] pause"); engine.setPaused(true) }
                DispatchQueue.main.asyncAfter(deadline: .now() + spec[0] + spec[1]) { debugLog("[test] resume, \(String(format: "%.1f", engine.progress.behindLive)) s behind"); engine.setPaused(false) }
            }
            if let spec = ProcessInfo.processInfo.environment["IPTV_TESTGOLIVE"].flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + spec) { debugLog("[test] go live"); engine.goLive() }
            }
            if let target = ProcessInfo.processInfo.environment["IPTV_TESTSEEK"].flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { engine.seek(to: target) }
            }
            if let spec = ProcessInfo.processInfo.environment["IPTV_TESTPIP"]?.split(separator: ":"), let start = Double(spec[0]) {
                // IPTV_TESTPIP=<s>[:back:<s>]: start Picture in Picture, optionally return to the
                // player. Closing needs the PiP window's close button: ending PiP from code always
                // counts as "back".
                DispatchQueue.main.asyncAfter(deadline: .now() + start) {
                    debugLog("[test] pip start, possible: \(pipPossible)")
                    pip?.toggle()
                }
                if spec.count == 3, spec[1] == "back", let after = Double(spec[2]) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + start + after) {
                        debugLog("[test] pip back")
                        pip?.restore()
                    }
                }
            }
            if let id = ProcessInfo.processInfo.environment["IPTV_TESTSUB"].flatMap(Int32.init) {
                // IPTV_TESTSUB=<track id>: choose that subtitle track after 6 s.
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    let track = engine.media?.subtitleTracks.first { $0.id == id }
                    debugLog("[test] subtitle \(id): \(track?.title ?? "not listed")")
                    if let track { pick(subtitle: track) }
                }
            }
            if let spec = ProcessInfo.processInfo.environment["IPTV_TESTAUDIO"] {
                // IPTV_TESTAUDIO=<at s>:<track id>,…: switch audio tracks at those times.
                for step in spec.split(separator: ",") {
                    let p = step.split(separator: ":").compactMap { Double($0) }
                    guard p.count == 2 else { continue }
                    DispatchQueue.main.asyncAfter(deadline: .now() + p[0]) {
                        let track = engine.media?.audioTracks.first { $0.id == Int32(p[1]) }
                        debugLog("[test] audio \(Int(p[1])): \(track?.title ?? "not listed")")
                        if let track { pick(audio: track) }
                    }
                }
            }
            if let path = ProcessInfo.processInfo.environment["IPTV_TESTCUES"], let srt = try? String(contentsOfFile: path, encoding: .utf8) {
                // IPTV_TESTCUES=<srt file>: show these cues after 4 s (overlapping cues).
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { engine.showExternalSubtitles(SRTParser.parse(srt), trackId: 9_999) }
            }
            #endif
        }
        .onChange(of: app.nowPlaying) { _, item in load(item) }
        .onReceive(pip?.$isPossible.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { pipPossible = $0 }
        .onDisappear {
            zapTask?.cancel()
            zapTarget = nil
            osd = nil
            saveResume()
            stopJellyfin()
            engine.stop()
            loadedItem = nil
            app.nowPlaying = nil
        }
        .onReceive(resumeTimer) { _ in
            if engine.status == .playing { saveResume() }
        }
        .onChange(of: engine.status) { _, status in
            switch status {
            case .paused, .ended, .failed:
                saveResume()
                showControls(autoHide: false)
            case .playing:
                showControls()
            default:
                break
            }
        }
        .task(id: liveChannelID) { await refreshEPG() }
        // Track the real window state so the button icon also follows the green button, Esc and ⌃⌘F.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            if (note.object as? NSWindow) === playerWindow { isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if (note.object as? NSWindow) === playerWindow { isFullScreen = false }
        }
        .animation(.easeInOut(duration: 0.25), value: audioBadge)
    }

    private struct AudioBadge: Equatable {
        let text: String
        /// Temporary gap: audio resumes on its own, so show activity.
        let waiting: Bool
    }

    /// Why there is no sound, if there is a picture but no audio.
    private var audioBadge: AudioBadge? {
        guard engine.status == .playing || engine.status == .paused, let media = engine.media, media.hasVideo else { return nil }
        if !media.hasAudio { return AudioBadge(text: String(localized: "Sender ohne Ton"), waiting: false) }
        if engine.isAudioMissing { return AudioBadge(text: String(localized: "Kein Ton vom Sender – warte auf Ton …"), waiting: true) }
        return nil
    }

    // MARK: Loading

    private func load(_ item: PlayItem?) {
        guard item != loadedItem else { return }
        activeDrags = 0
        saveResume()
        stopJellyfin()
        loadedItem = item
        guard let item else {
            engine.stop()
            return
        }
        play(item)
        showControls()
        if item.isLive { announceCurrentChannel() } else { osd = nil }
    }

    private func play(_ item: PlayItem) {
        engine.trackPreferences = app.trackPreferences(for: item)
        if item.isLive, let tuner = app.playerTuner {
            engine.load(tuner: tuner)
        } else if case .jellyfin(let itemId, let startAt, _) = item.kind {
            stopJellyfin()
            Task { @MainActor in
                guard let playback = await JellyfinPlayback.make(itemId: itemId, store: jellyfin, engine: engine),
                      loadedItem == item else { return }
                jellyfinPlayback = playback
                playback.start(at: startAt)
            }
        } else if case .recording(let id) = item.kind {
            let start = item.resumeKey.map { app.resumePosition($0) } ?? 0
            engine.load(file: item.url, isGrowing: { Recorder.isGrowing(id) }, startAt: start)
        } else {
            let start = item.resumeKey.map { app.resumePosition($0) } ?? 0
            engine.load(url: item.url, isLive: item.isLive, startAt: start)
        }
    }

    // MARK: Track choice

    private func pick(audio track: MediaTrack) {
        let subtitle = engine.media.flatMap { m in m.subtitleTracks.first { $0.id == m.selectedSubtitle } }
        engine.selectAudio(track)
        remember(audio: track, subtitle: subtitle)
    }

    private func pick(subtitle track: MediaTrack?) {
        let audio = engine.media.flatMap { m in m.audioTracks.first { $0.id == m.selectedAudio } }
        engine.selectSubtitle(track)
        remember(audio: audio, subtitle: track)
    }

    /// The pick as language rules, so the next episode finds the same languages.
    private func remember(audio: MediaTrack?, subtitle: MediaTrack?) {
        guard let item = loadedItem else { return }
        var preferences = engine.trackPreferences
        if let language = audio?.language { preferences.audioLanguage = language }
        if let subtitle, let language = subtitle.language {
            if subtitle.isForced {
                preferences.subtitles = language == audio?.language ? .forcedOnly : .language(language)
            } else {
                preferences.subtitles = .full(language)
            }
        } else if subtitle == nil {
            preferences.subtitles = .off
        }
        engine.trackPreferences = preferences
        app.rememberTracks(preferences, for: item)
    }

    /// Reports the stop to Jellyfin (before the engine forgets the position).
    private func stopJellyfin() {
        jellyfinPlayback?.stop()
        jellyfinPlayback = nil
    }

    private func saveResume() {
        guard let item = loadedItem, let key = item.resumeKey else { return }
        let duration = engine.progress.duration
        guard duration > 0 else { return }
        let position = engine.status == .ended ? duration : engine.progress.position
        app.saveResume(key, position: position, duration: duration)
    }

    // MARK: EPG

    private var liveChannelID: Int? {
        if case .live(let id, _)? = app.nowPlaying?.kind { return id }
        return nil
    }

    private var currentEPG: EPGEntry? {
        epg.first { $0.start <= Date() && $0.end > Date() }
    }

    private func refreshEPG() async {
        epg = []
        guard let id = liveChannelID else { return }
        while !Task.isCancelled {
            epg = (try? await app.client?.shortEPG(id, limit: 3)) ?? epg
            try? await Task.sleep(for: .seconds(60))
        }
    }

    // MARK: Recording

    /// Records the show on now (from its start, as far as the buffer reaches), or stops.
    private func toggleRecording() {
        guard let id = liveChannelID, let channel = app.channel(id) else { return }
        if let running = recorder.active(on: id) {
            recorder.stop(running.id)
        } else {
            recorder.recordNow(channel, entry: currentEPG)
        }
    }

    // MARK: Controls visibility

    private func showControls() {
        showControls(autoHide: true)
    }

    private func showControls(autoHide: Bool) {
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.15)) { controlsVisible = true }
        }
        hideTask?.cancel()
        guard autoHide, activeDrags == 0 else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_KEEPCONTROLS"] != nil { return }
        #endif
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, engine.status == .playing else { return }
            withAnimation(.easeIn(duration: 0.3)) { controlsVisible = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    /// The window hosting the video, independent of which window is key.
    private var playerWindow: NSWindow? {
        NSApp.windows.first { $0.contentView?.firstDescendant(of: VideoSurfaceView.self) != nil }
    }

    // MARK: Picture in Picture

    /// The PiP window takes over the display layer; the player window hides meanwhile (not
    /// closed – that would stop playback) and comes back on "back". Closing PiP ends playback the
    /// same way as closing the player window.
    private func setUpPictureInPicture() {
        guard pip == nil else { return }
        let controller = PictureInPicture(engine: engine)
        // The view sizes the layer to the exact display aspect (non-square pixels); PiP sizes it
        // to its own window, so the layer keeps the aspect itself meanwhile.
        controller.onWillStart = {
            engine.displayLayer.videoGravity = .resizeAspect
            if let surface = playerWindow?.contentView?.firstDescendant(of: VideoSurfaceView.self) { pipStage.prepare(surface: surface) }
        }
        controller.onStarted = {
            pipStage.begin()
            playerWindow?.orderOut(nil)
        }
        controller.onRestore = {
            pipStage.end()
            engine.displayLayer.videoGravity = .resize
            playerWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            showControls()
        }
        controller.onClosed = {
            pipStage.end()
            engine.displayLayer.videoGravity = .resize
            guard let window = playerWindow else { return }
            window.orderFront(nil)
            window.performClose(nil)
        }
        pip = controller
    }

    private func toggleFullScreen() {
        guard let window = playerWindow else { return }
        // SwiftUI treats single-instance `Window` scenes as auxiliary and keeps resetting the
        // collection behaviour; auxiliary windows cannot get their own full-screen space.
        window.collectionBehavior.remove([.fullScreenAuxiliary, .auxiliary])
        window.collectionBehavior.insert([.fullScreenPrimary, .primary])
        window.toggleFullScreen(nil)
    }

    // MARK: Zapping

    private func zap(_ offset: Int) {
        guard case .live(let currentId, let categoryId)? = app.nowPlaying?.kind else { return }
        let fromId = zapTarget?.channel.id ?? currentId
        guard let target = app.neighbor(of: fromId, categoryId: categoryId, offset: offset) else { return }
        zapTarget = target
        showOSD(target, autoHide: false)
        zapTask?.cancel()
        zapTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let pending = zapTarget else { return }
            zapTarget = nil
            app.play(pending.channel)
            showOSD(pending, autoHide: true)
        }
    }

    /// Shows the channel banner; with `autoHide` it disappears after a few seconds.
    private func showOSD(_ entry: (channel: LiveChannel, number: Int), autoHide: Bool) {
        withAnimation(.easeOut(duration: 0.15)) { osd = entry }
        osdHideTask?.cancel()
        guard autoHide else { return }
        osdHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, zapTarget == nil else { return }
            withAnimation(.easeIn(duration: 0.3)) { osd = nil }
        }
    }

    /// Banner for channels opened from the library (not only when zapping).
    private func announceCurrentChannel() {
        guard zapTarget == nil, case .live(let id, let categoryId)? = app.nowPlaying?.kind,
              let current = app.neighbor(of: id, categoryId: categoryId, offset: 0) else { return }
        showOSD(current, autoHide: true)
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        let live = engine.isLive
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 49: // space
            engine.togglePause()
        case 123: // left
            guard !live || engine.isTimeshift else { return false }
            engine.seek(by: shift ? -60 : -10)
        case 124: // right
            guard !live || engine.isTimeshift else { return false }
            engine.seek(by: shift ? 60 : 10)
        case 126: // up
            if live { zap(-1) } else { engine.volume = min(1, engine.volume + 0.05) }
        case 125: // down
            if live { zap(1) } else { engine.volume = max(0, engine.volume - 0.05) }
        case 116: // page up
            zap(-1)
        case 121: // page down
            zap(1)
        case 53: // escape
            guard let window = playerWindow, window.styleMask.contains(.fullScreen) else { return false }
            window.toggleFullScreen(nil)
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f": toggleFullScreen()
            case "p": pip?.toggle()
            case "i": showInfo.toggle()
            case "r" where live: toggleRecording()
            case "m": engine.isMuted.toggle()
            case "+": engine.volume = min(1, engine.volume + 0.05)
            case "-": engine.volume = max(0, engine.volume - 0.05)
            default: return false
            }
        }
        showControls()
        return true
    }

    // MARK: Status

    @ViewBuilder
    private var statusOverlay: some View {
        switch engine.status {
        case .loading, .buffering:
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(.white)
                if engine.isReconnecting {
                    Text("Verbindung wird wiederhergestellt …").foregroundStyle(.white.opacity(0.8))
                } else if engine.status == .loading {
                    Text("Verbinde …").foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(24)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            .allowsHitTesting(false)
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.yellow)
                Text(message).foregroundStyle(.white).multilineTextAlignment(.center)
                Button("Erneut versuchen") {
                    if let item = loadedItem {
                        if item.isLive { app.retuneForPlayer() }
                        play(item)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
        case .ended:
            Button {
                engine.setPaused(false)
            } label: {
                Label("Erneut abspielen", systemImage: "arrow.counterclockwise")
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        default:
            EmptyView()
        }
    }
}

// MARK: - Controls

struct PlayerControls: View {
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var progress: PlaybackProgress
    let item: PlayItem
    let epg: EPGEntry?
    @Binding var showInfo: Bool
    let isFullScreen: Bool
    /// Hidden while the channel banner shows the same information.
    let showsTitle: Bool
    let onZap: (Int) -> Void
    let onFullScreen: () -> Void
    let onActivity: () -> Void
    /// Live: the current show is being recorded; nil when recording is not possible.
    var isRecording: Bool? = nil
    var onRecord: () -> Void = {}
    /// Menu picks go through the screen, which remembers them for the series.
    var onPickAudio: (MediaTrack) -> Void = { _ in }
    var onPickSubtitle: (MediaTrack?) -> Void = { _ in }
    /// A slider drag starts (true) or ends (false); reported before the activity.
    var onDragging: (Bool) -> Void = { _ in }
    var pipPossible = false
    var onPictureInPicture: () -> Void = {}

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar.opacity(showsTitle ? 1 : 0)
            Spacer(minLength: 0)
            bottomBar
        }
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    if item.isLive {
                        let live = progress.followsLive
                        Text(live ? "LIVE" : "ZEITVERSETZT")
                            .font(.caption.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(live ? Color.red : Color.gray, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if isRecording == true {
                        Label("REC", systemImage: "record.circle.fill")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                            .fixedSize()
                    }
                    Text(item.title).font(.title2.weight(.semibold)).lineLimit(1)
                }
                if let subtitle = item.subtitle {
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
                if let epg {
                    HStack(spacing: 8) {
                        Text("\(epg.start.formatted(date: .omitted, time: .shortened)) – \(epg.end.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(epg.title).lineLimit(1)
                    }
                    ProgressView(value: epg.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                        .tint(.white)
                }
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 40)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    /// Timeshift: what can be played, from the oldest buffered second to the live edge.
    private var liveRange: ClosedRange<Double>? {
        guard engine.isTimeshift else { return nil }
        let end = progress.liveEnd - PlayerEngine.liveLead
        guard end - progress.liveStart > 10 else { return nil }
        return progress.liveStart...end
    }

    private var timeshiftBar: some View {
        HStack(spacing: 12) {
            Text((progress.wallClock ?? Date()).formatted(date: .omitted, time: .standard))
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
            Slider(value: Binding(
                // Following live sits at the end; the real position wobbles with bursty delivery.
                get: { scrubbing ? scrubValue : (progress.followsLive ? (liveRange?.upperBound ?? progress.position) : progress.position) },
                set: { scrubValue = $0 }
            ), in: liveRange ?? 0...1) { editing in
                if editing {
                    scrubValue = progress.followsLive ? (liveRange?.upperBound ?? progress.position) : progress.position
                    scrubbing = true
                } else {
                    // Let go at the end: back to live, not to a fixed point just before it.
                    if let range = liveRange, scrubValue >= range.upperBound - 1 { engine.goLive() } else { engine.seek(to: scrubValue) }
                    scrubbing = false
                }
                onDragging(editing)
                onActivity()
            }
            .controlSize(.small)
            Button {
                engine.goLive()
                onActivity()
            } label: {
                let behind = scrubbing ? max(0, (liveRange?.upperBound ?? 0) - scrubValue) : progress.behindLive
                let live = scrubbing ? behind < 1 : progress.followsLive
                Text(live ? String(localized: "LIVE") : "−" + formatTime(behind))
                    .monospacedDigit()
                    .font(.callout.weight(live ? .bold : .regular))
                    .foregroundStyle(live ? Color.red : Color.white)
                    .frame(minWidth: 64, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Zurück zu Live")
        }
        .font(.callout)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if liveRange != nil {
                timeshiftBar
            }
            if !item.isLive && progress.duration > 0 {
                HStack(spacing: 12) {
                    Text(formatTime(scrubbing ? scrubValue : progress.position))
                        .monospacedDigit()
                        .frame(minWidth: 56, alignment: .trailing)
                    Slider(value: Binding(
                        get: { scrubbing ? scrubValue : progress.position },
                        set: { scrubValue = $0 }
                    ), in: 0...max(progress.duration, 1)) { editing in
                        if editing {
                            scrubValue = progress.position
                            scrubbing = true
                        } else {
                            engine.seek(to: scrubValue)
                            scrubbing = false
                        }
                        onDragging(editing)
                        onActivity()
                    }
                    .controlSize(.small)
                    Text("-" + formatTime(max(0, progress.duration - (scrubbing ? scrubValue : progress.position))))
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .leading)
                }
                .font(.callout)
            }

            HStack(spacing: 18) {
                if item.isLive {
                    iconButton("chevron.up", help: "Vorheriger Sender (↑)") { onZap(-1) }
                    iconButton("chevron.down", help: "Nächster Sender (↓)") { onZap(1) }
                }
                if !item.isLive || engine.isTimeshift {
                    iconButton("gobackward.10", help: "10 s zurück (←)") { engine.seek(by: -10) }
                }

                Button {
                    engine.togglePause()
                    onActivity()
                } label: {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 26))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .help("Wiedergabe/Pause (Leertaste)")

                if !item.isLive || engine.isTimeshift {
                    iconButton("goforward.10", help: "10 s vor (→)") { engine.seek(by: 10) }
                        .disabled(item.isLive && progress.followsLive)
                }

                if let isRecording {
                    Button {
                        onRecord()
                        onActivity()
                    } label: {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .foregroundStyle(isRecording ? Color.red : Color.white)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help(isRecording ? "Aufnahme beenden (R)" : "Laufende Sendung aufnehmen (R)")
                }

                Spacer()

                if let media = engine.media {
                    if media.audioTracks.count > 1 {
                        let current = media.audioTracks.first { $0.id == media.selectedAudio }
                        Menu {
                            // An inline picker: real menu checkmarks for the selected track.
                            Picker("Tonspur", selection: Binding(
                                get: { media.selectedAudio },
                                set: { id in if let track = media.audioTracks.first(where: { $0.id == id }) { onPickAudio(track) } }
                            )) {
                                ForEach(media.audioTracks) { track in Text(track.title).tag(Optional(track.id)) }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } label: {
                            Image(systemName: "waveform.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Tonspur: \(current?.title ?? "–")")
                    }
                    if !media.subtitleTracks.isEmpty {
                        let current = media.subtitleTracks.first { $0.id == media.selectedSubtitle }
                        Menu {
                            Picker("Untertitel", selection: Binding(
                                get: { media.selectedSubtitle },
                                set: { id in onPickSubtitle(media.subtitleTracks.first { $0.id == id }) }
                            )) {
                                Text("Aus").tag(Int32?.none)
                                ForEach(media.subtitleTracks) { track in Text(track.title).tag(Optional(track.id)) }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } label: {
                            Image(systemName: current != nil ? "captions.bubble.fill" : "captions.bubble")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help(current.map { String(localized: "Untertitel: \($0.title)") } ?? String(localized: "Untertitel: Aus"))
                    }
                }

                if pipPossible {
                    iconButton("pip.enter", help: "Bild in Bild (P)") { onPictureInPicture() }
                }
                iconButton(showInfo ? "info.circle.fill" : "info.circle", help: "Technische Infos (I)") { showInfo.toggle() }

                HStack(spacing: 6) {
                    Button {
                        engine.isMuted.toggle()
                    } label: {
                        Image(systemName: volumeIcon).frame(width: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Ton aus (M)")
                    Slider(value: Binding(get: { Double(engine.volume) }, set: { engine.volume = Float($0); onActivity() }), in: 0...1) { editing in
                        onDragging(editing)
                        onActivity()
                    }
                        .frame(width: 90)
                        .controlSize(.mini)
                }

                iconButton(isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           help: isFullScreen ? "Vollbild beenden (F, Esc)" : "Vollbild (F)") { onFullScreen() }
            }
            .font(.system(size: 17))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: 980)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .onHover { if $0 { onActivity() } }
    }

    private var volumeIcon: String {
        if engine.isMuted || engine.volume == 0 { return "speaker.slash.fill" }
        if engine.volume < 0.34 { return "speaker.wave.1.fill" }
        if engine.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onActivity()
        } label: {
            Image(systemName: symbol).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// TV-style channel banner: number, logo, name and what is on now.
struct ChannelOSD: View {
    @EnvironmentObject private var app: AppModel
    let channel: LiveChannel
    let number: Int
    /// Still choosing (key presses continue); the channel is not tuned yet.
    let isPending: Bool
    @State private var now: EPGEntry?

    var body: some View {
        HStack(spacing: 16) {
            Text("\(number)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 52)
            RemoteImage(url: channel.icon, maxPixel: 160, contentMode: .fit) {
                Image(systemName: "tv").font(.title).foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(channel.name).font(.title3.weight(.semibold)).lineLimit(1)
                    if isPending {
                        ProgressView().controlSize(.small).tint(.white).opacity(0.7)
                    }
                }
                if let now {
                    HStack(spacing: 8) {
                        Text("\(now.start.formatted(date: .omitted, time: .shortened)) – \(now.end.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(now.title).lineLimit(1)
                    }
                    .font(.callout)
                    ProgressView(value: now.progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 240)
                }
            }
            .frame(minWidth: 220, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: 560, alignment: .leading)
        .task(id: channel.id) {
            now = nil
            // Short debounce: no EPG request for channels that are only skipped past.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let entries = (try? await app.client?.shortEPG(channel.id, limit: 2)) ?? []
            now = entries.first { $0.start <= Date() && $0.end > Date() } ?? entries.first
        }
    }
}

struct AudioStatusBadge: View {
    let text: String
    let waiting: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.slash.fill")
            Text(text)
            if waiting {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            .environment(\.colorScheme, .dark)
            .help(waiting ? String(localized: "Der Sender liefert gerade keine Tondaten. Der Ton setzt automatisch wieder ein.")
                          : String(localized: "Dieser Sender überträgt keine Tonspur."))
    }
}

struct StatsOverlay: View {
    let stats: PlaybackStats
    let status: PlayerEngine.Status
    @ObservedObject var history: BufferHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            grid
            BufferChart(history: history, isTimeshift: stats.timeshiftAhead != nil)
        }
        // Size to the content instead of stretching (the divider would take the full width).
        .fixedSize()
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            if let method = stats.playMethod { row("Wiedergabe", method) }
            row("Container", stats.container)
            row("Video", stats.videoCodec)
            row("Auflösung", stats.resolution)
            row("Bildrate", stats.frameRate > 0 ? String(format: "%.2f fps", stats.frameRate) : "–")
            row("Dekoder", stats.decoder)
            row("Pixelformat", stats.pixelFormat)
            row("Dynamik", stats.dynamicRange)
            row("Deinterlacing", stats.deinterlace.isEmpty ? "–" : stats.deinterlace)
            row("Audio", stats.audio)
            row("Datenrate", String(format: "%.1f Mbit/s", stats.bitrateMbps))
            Divider().overlay(.white.opacity(0.25)).gridCellColumns(2)
            row("Puffer", bufferText)
            if let stored = stats.timeshiftStored {
                row("Zeitpuffer", String(localized: "\(formatTime(stored)) gespeichert"))
            }
            row("Verbindung", stats.connectTime > 0 ? String(format: String(localized: "%.0f ms bis Antwort"), stats.connectTime * 1000) : "")
            row("Startzeit", stats.startupTime > 0 ? String(format: String(localized: "%.1f s bis zum Bild"), stats.startupTime) : "")
            row("Reconnects", reconnectText)
            row("Pufferungen", "\(stats.rebuffers)")
            row("Verworfen", String(localized: "\(stats.droppedFrames) Frames") + (stats.duplicatesDropped > 0 ? " · " + String(localized: "\(stats.duplicatesDropped) Duplikate") : ""))
        }
    }

    private var bufferText: String {
        if let ahead = stats.timeshiftAhead {
            let disk = ahead >= 60 ? formatTime(ahead) : String(format: "%.1f s", ahead)
            return String(format: "%.1f s", stats.bufferSeconds) + " + " + String(localized: "Platte \(disk)")
        }
        let network = Double(stats.networkBufferBytes)
        let networkText = network >= 1_000_000 ? String(format: "%.1f MB", network / 1_000_000) : String(format: "%.0f KB", network / 1000)
        // Network bytes in seconds at the average data rate, when it is known.
        let rate = history.averageMbps * 125_000
        let networkSeconds = rate > 0 ? String(format: " ≈ %.1f s", network / rate) : ""
        return String(format: "%.1f s", stats.bufferSeconds) + " + " + String(localized: "Netz \(networkText)\(networkSeconds)")
    }

    private var reconnectText: String {
        var parts = [String(localized: "\(stats.seamlessReconnects) nahtlos")]
        if stats.restarts > 0 { parts.append(String(localized: "\(stats.restarts) Neustarts")) }
        var text = parts.joined(separator: " · ")
        if stats.isReconnecting {
            text += " · " + String(localized: "verbindet …")
        } else if let at = stats.lastReconnectAt {
            let ago = Int(Date().timeIntervalSince(at))
            let when = ago < 60 ? String(localized: "vor \(ago) s") : String(localized: "vor \(ago / 60) min")
            text += "\n" + String(localized: "zuletzt \(when): \(stats.lastReconnectReason ?? "")")
        }
        return text
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Text(value.isEmpty ? "–" : value)
        }
    }
}

/// Buffer over the last two minutes: player and network share stacked, the reconnect
/// threshold dashed, and reconnects, restarts and stalls marked.
struct BufferChart: View {
    @ObservedObject var history: BufferHistory
    /// The second share is what the timeshift buffer holds ahead, not network bytes.
    var isTimeshift = false
    /// Timeshifted playback can have hours ahead; the chart is about the last seconds.
    private static let cap = 60.0

    private static let playerColor = Color(red: 0.35, green: 0.62, blue: 1.0)
    private static let networkColor = Color(red: 0.55, green: 0.85, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Puffer, letzte 2 min").foregroundStyle(.white.opacity(0.6))
                Spacer()
                legend(Self.playerColor, "Player")
                legend(Self.networkColor, isTimeshift ? "Platte" : "Netz")
            }
            chart.frame(width: 300, height: 90)
            HStack(spacing: 10) {
                legend(.orange, "Reconnect")
                legend(.purple, "Neustart")
                legend(.red, "Pufferung")
                Spacer()
            }
            .font(.system(size: 9, design: .monospaced))
        }
        .frame(width: 300)
    }

    private var chart: some View {
        let now = history.samples.last?.time ?? Date()
        let samples = history.samples
        let peak = min(Self.cap, samples.map { $0.player + $0.network }.max() ?? 0)
        return Chart {
            ForEach(samples) { sample in
                let x = sample.time.timeIntervalSince(now)
                AreaMark(x: .value("Zeit", x), y: .value("Sekunden", sample.player), stacking: .standard)
                    .foregroundStyle(by: .value("Anteil", "Player"))
                AreaMark(x: .value("Zeit", x), y: .value("Sekunden", min(sample.network, max(0, Self.cap - sample.player))), stacking: .standard)
                    .foregroundStyle(by: .value("Anteil", "Netz"))
                ForEach(Array(sample.events.enumerated()), id: \.offset) { _, event in
                    RuleMark(x: .value("Zeit", x))
                        .foregroundStyle(Self.color(for: event))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            RuleMark(y: .value("Schwelle", 4))
                .foregroundStyle(.white.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartForegroundStyleScale(["Player": Self.playerColor.opacity(0.8), "Netz": Self.networkColor.opacity(0.7)])
        .chartLegend(.hidden)
        .chartXScale(domain: -BufferHistory.window...0)
        .chartYScale(domain: 0...max(10, (peak / 5).rounded(.up) * 5))
        .chartXAxis {
            AxisMarks(values: [-120, -90, -60, -30, 0]) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(seconds == 0 ? "jetzt" : "\(Int(seconds)) s")
                    }
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) { Text("\(Int(seconds)) s") }
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 9, design: .monospaced))
    }

    private static func color(for event: BufferHistory.Event) -> Color {
        switch event {
        case .reconnect: return .orange
        case .restart: return .purple
        case .rebuffer: return .red
        }
    }

    private func legend(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.white.opacity(0.7))
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for child in subviews {
            if let match = child.firstDescendant(of: type) { return match }
        }
        return nil
    }
}

/// After an episode: the next one with a countdown.
private struct NextEpisodeOverlay: View {
    @ObservedObject var playback: JellyfinPlayback
    let bottomInset: CGFloat
    let play: (JFItem) -> Void
    @State private var remaining = 10
    @State private var cancelled = false

    var body: some View {
        if let next = playback.nextEpisode, !cancelled {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nächste Folge").font(.headline).foregroundStyle(.secondary)
                Text(label(next)).font(.title2.weight(.semibold)).lineLimit(2)
                HStack {
                    Button("Jetzt abspielen (\(remaining))") { play(next) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button("Abbrechen") { cancelled = true }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(22)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 32)
            .padding(.bottom, bottomInset)
            .animation(.easeOut(duration: 0.2), value: bottomInset)
            .task(id: next.id) {
                remaining = 10
                while remaining > 0 && !cancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if !cancelled { remaining -= 1 }
                }
                if !cancelled { play(next) }
            }
        }
    }

    private func label(_ item: JFItem) -> String {
        let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined()
        return code.isEmpty ? item.name : "\(code) · \(item.name)"
    }
}

/// Draws a bitmap subtitle (PGS, VobSub, DVB) over the picture, placed on the subtitle's canvas
/// scaled to where the video is shown (letterboxing included).
struct BitmapSubtitleView: View {
    let cue: BitmapCue
    let videoSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let video = fitted(videoSize, in: geo.size)
            let canvas = cue.canvas.width > 0 && cue.canvas.height > 0 ? cue.canvas : videoSize
            let scale = canvas.width > 0 ? video.width / canvas.width : 1
            let scaleY = canvas.height > 0 ? video.height / canvas.height : scale
            ZStack(alignment: .topLeading) {
                ForEach(Array(cue.pieces.enumerated()), id: \.offset) { _, piece in
                    Image(decorative: piece.image, scale: 1)
                        .resizable()
                        .frame(width: piece.rect.width * scale, height: piece.rect.height * scaleY)
                        .offset(x: video.minX + piece.rect.minX * scale, y: video.minY + piece.rect.minY * scaleY)
                }
            }
        }
    }

    private func fitted(_ content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }
}
