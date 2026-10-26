import AppIntents
import Charts
import Combine
import FernsyCore
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
    /// Live playback has been buffering for a second (short stalls stay a plain spinner).
    @State private var stallCardVisible = false
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
    // The channel list over the picture (live TV, L).
    @State private var showsChannelList = false
    @State private var listCategory = allCategoryID
    @State private var listHighlight: Int?
    @State private var listHideTask: Task<Void, Never>?
    private static let channelListWidth: CGFloat = 340

    private let resumeTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var playingChannelEntity: EntityIdentifier? {
        guard case .live(let id, _)? = app.nowPlaying?.kind else { return nil }
        return EntityIdentifier(for: ChannelEntity.self, identifier: id)
    }

    var body: some View {
        ZStack {
            Color.black

            VideoSurface(engine: engine, onKeyDown: handleKey, onMouseActivity: showControls, onDoubleClick: toggleFullScreen,
                         onClick: { if showsChannelList { closeChannelList() } })

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
                    // Beside the channel list while it is open.
                    .padding(.leading, showsChannelList ? Self.channelListWidth + 40 : 24)
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    .allowsHitTesting(false)
            }

            if engine.showsServerSwitchNote {
                Label("Another server of the provider delivers smoothly again.", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                PlayerControls(engine: engine, progress: engine.progress, item: item, entries: epg,
                               showInfo: $showInfo, isFullScreen: isFullScreen, showsTitle: osd == nil && !showsChannelList, onZap: zap, onFullScreen: toggleFullScreen,
                               onChannelList: toggleChannelList,
                               onActivity: showControls,
                               recordingEnd: liveChannelID.flatMap { recorder.active(on: $0)?.recordEnd },
                               canRecord: liveChannelID != nil,
                               onRecord: toggleRecording, onPickAudio: { pick(audio: $0) }, onPickSubtitle: { pick(subtitle: $0) },
                               onDragging: { dragging in activeDrags = max(0, activeDrags + (dragging ? 1 : -1)) },
                               pipPossible: pipPossible && [.playing, .paused, .buffering].contains(engine.status), onPictureInPicture: { pip?.toggle() })
                    .transition(.opacity)
            }

            if showsChannelList, let playing = liveChannelID {
                PlayerChannelList(categoryID: $listCategory, highlighted: listHighlight, playingID: playing,
                                  onTune: tuneFromList, onActivity: restartChannelListTimer)
                    .containerRelativeFrame(.horizontal) { width, _ in min(Self.channelListWidth, width * 0.45) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.top, 40)
                    // Clear of the control panel (timeline, programme line and buttons).
                    .padding(.bottom, controlsVisible ? 200 : 24)
                    .transition(.move(edge: .leading).combined(with: .opacity))
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
        .navigationTitle(app.nowPlaying?.title ?? "Playback")
        .onAppear {
            app.playerEngine = engine
            PlayerWindow.appeared()
            setUpPictureInPicture()
            load(app.nowPlaying)
            showControls()
            #if DEBUG
            if ProcessInfo.processInfo.environment["IPTV_SHOWINFO"] != nil { showInfo = true }
            if let spec = ProcessInfo.processInfo.environment["IPTV_TESTCHANNELLIST"] {
                // IPTV_TESTCHANNELLIST=<s>[:<key>,…]: opens the channel list after s seconds, then
                // feeds the keys (down, up, pagedown, return, esc, l, category:<id>) one per second
                // through the screen's own key handling; no events reach the system.
                let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
                let start = Double(parts[0]) ?? 5
                let keys = parts.count > 1 ? parts[1].split(separator: ",").map(String.init) : []
                DispatchQueue.main.asyncAfter(deadline: .now() + start) { toggleChannelList() }
                for (i, key) in keys.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + start + 1 + Double(i)) {
                        AppLog.detail(.player, "[test] key \(key)")
                        if key.hasPrefix("category:") {
                            listCategory = String(key.dropFirst("category:".count))
                            listHighlight = PlayerChannelList.channels(listCategory, app: app).first?.id
                            restartChannelListTimer()
                            return
                        }
                        let codes: [String: UInt16] = ["down": 125, "up": 126, "pagedown": 121, "return": 36, "esc": 53, "l": 37]
                        guard let code = codes[key] else { return }
                        if showsChannelList, handleChannelListKey(code) { return }
                        // Closed: the same keys as without the list.
                        switch key {
                        case "down": zap(1)
                        case "up": zap(-1)
                        case "l": toggleChannelList()
                        default: break
                        }
                    }
                }
            }
            if ProcessInfo.processInfo.environment["IPTV_TESTZAP"] != nil {
                for i in 0..<3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6 + Double(i) * 0.15) {
                        AppLog.detail(.player, "key down #\(i + 1)")
                        zap(1)
                        AppLog.detail(.player, "target \(zapTarget.map { "\($0.channel.id) (#\($0.number))" } ?? "-")")
                    }
                }
            }
            if ProcessInfo.processInfo.environment["IPTV_TESTFS"] != nil {
                // Enter, leave and re-enter full screen to exercise repeated toggling.
                for (delay, label) in [(6.0, "enter"), (10.0, "leave"), (14.0, "re-enter")] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { toggleFullScreen() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.5) {
                        AppLog.detail(.player, "after \(label): fullscreen=\(playerWindow?.styleMask.contains(.fullScreen) ?? false) iconState=\(isFullScreen)")
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
                    debugLog("[test] pip start, possible: \(pip?.canStart ?? false)")
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
        // Onscreen context for Siri: "Nimm das in Fernsy auf" refers to the channel shown here.
        .appEntityIdentifier(playingChannelEntity)
        .onChange(of: app.nowPlaying) { _, item in load(item) }
        .onReceive(pip?.$isPossible.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { pipPossible = $0 }
        .onDisappear {
            if app.playerEngine === engine { app.playerEngine = nil }
            // Closed in full screen: no exit notification comes.
            LibraryWindows.restore(below: nil)
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
                if app.isPictureInPictureActive { pipStage.refit() }
            default:
                break
            }
        }
        .onChange(of: engine.videoSize) { _, _ in
            if app.isPictureInPictureActive { pipStage.refit() }
        }
        .onChange(of: engine.media?.hasVideo) { _, hasVideo in
            // Nothing to show in PiP (radio): back to the player window.
            if hasVideo == false, app.isPictureInPictureActive { pip?.restore() }
        }
        .task(id: liveChannelID) { await refreshEPG() }
        .task(id: engine.status == .buffering && loadedItem?.isLive == true) {
            stallCardVisible = false
            guard engine.status == .buffering, loadedItem?.isLive == true else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { stallCardVisible = true }
        }
        // Track the real window state so the button icon also follows the green button, Esc and ⌃⌘F.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            if (note.object as? NSWindow) === playerWindow {
                isFullScreen = true
                LibraryWindows.hideForFullScreen()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if (note.object as? NSWindow) === playerWindow {
                isFullScreen = false
                LibraryWindows.restore(below: playerWindow)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: audioBadge)
        .animation(.easeInOut(duration: 0.25), value: engine.showsServerSwitchNote)
    }

    private struct AudioBadge: Equatable {
        let text: String
        /// Temporary gap: audio resumes on its own, so show activity.
        let waiting: Bool
    }

    /// Why there is no sound, if there is a picture but no audio.
    private var audioBadge: AudioBadge? {
        guard engine.status == .playing || engine.status == .paused, let media = engine.media, media.hasVideo else { return nil }
        if !media.hasAudio { return AudioBadge(text: String(localized: "Channel without audio"), waiting: false) }
        if engine.isAudioMissing { return AudioBadge(text: String(localized: "No audio from channel – waiting…"), waiting: true) }
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
        // The PiP window would keep the previous item's last picture while this one loads.
        if app.isPictureInPictureActive {
            if case .live(let id, _) = item.kind, let channel = app.channel(id) {
                // Whatever size of this logo is already decoded (the list, guide or banner loaded it).
                let url = channel.icon.flatMap(URL.init(string:))
                let image = url.flatMap { url in
                    [156, 240, 132, 198, 144, 216, 192, 450].lazy.compactMap { ImagePipeline.shared.cached(url, maxPixel: $0) }.first
                }
                engine.loadingCard.start(title: channel.displayName, over: engine.lastPicture.value,
                                         logo: image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                                         initials: LogoTile.initials(of: channel.displayName),
                                         lightTile: url.flatMap { ImagePipeline.shared.tone(for: $0) } == .darkOnClear)
            } else {
                engine.loadingCard.start(title: item.title, over: engine.lastPicture.value)
            }
            pipStage.refit()
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
                app.jellyfinPlayback = playback
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
        if app.jellyfinPlayback === jellyfinPlayback { app.jellyfinPlayback = nil }
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
            // The full schedule: the timeline marks shows across the whole buffer.
            await app.epg.load(id, client: app.client)
            if let entries = app.epg.guide(id).entries, !entries.isEmpty {
                epg = entries
            } else {
                epg = (try? await app.client?.shortEPG(id, limit: 3)) ?? epg
            }
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
            recorder.recordNow(channel, entry: currentEPG).present()
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
            app.isPictureInPictureActive = true
            pipStage.begin()
            playerWindow?.orderOut(nil)
        }
        controller.onRestore = {
            app.isPictureInPictureActive = false
            pipStage.end(flushing: engine.videoSink)
            engine.displayLayer.videoGravity = .resize
            playerWindow?.makeKeyAndOrderFront(nil)
            AppActivation.activate()
            showControls()
        }
        controller.onClosed = {
            app.isPictureInPictureActive = false
            pipStage.end(flushing: engine.videoSink)
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

    // MARK: Channel list

    private func toggleChannelList() {
        if showsChannelList { closeChannelList(); return }
        guard case .live(let id, let categoryId)? = app.nowPlaying?.kind else { return }
        listCategory = categoryId ?? allCategoryID
        listHighlight = id
        withAnimation(.easeOut(duration: 0.2)) { showsChannelList = true }
        AppLog.detail(.player, "channel list opened (\(listCategory))")
        restartChannelListTimer()
    }

    private func closeChannelList() {
        listHideTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { showsChannelList = false }
        AppLog.detail(.player, "channel list closed")
    }

    /// Closes the list after 10 s without interaction with it.
    private func restartChannelListTimer() {
        listHideTask?.cancel()
        listHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, showsChannelList else { return }
            closeChannelList()
        }
    }

    /// Keys while the list is open: ↑/↓ and Page Up/Down move the highlight, Return tunes,
    /// L and Esc close it. Other keys keep their meaning.
    private func handleChannelListKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 126: moveListHighlight(by: -1)
        case 125: moveListHighlight(by: 1)
        case 116: moveListHighlight(by: -8)
        case 121: moveListHighlight(by: 8)
        case 36, 76: // return, enter
            if let id = listHighlight, let channel = PlayerChannelList.channels(listCategory, app: app).first(where: { $0.id == id }) {
                tuneFromList(channel)
            }
        case 53, 37: closeChannelList() // escape, L
        default: return false
        }
        if showsChannelList { restartChannelListTimer() }
        return true
    }

    private func moveListHighlight(by offset: Int) {
        let list = PlayerChannelList.channels(listCategory, app: app)
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == listHighlight }.map { $0 + offset } ?? 0
        listHighlight = list[min(max(index, 0), list.count - 1)].id
        AppLog.detail(.player, "channel list highlight \(listHighlight ?? 0)")
    }

    /// Tunes like zapping, with the banner; the list stays open and follows the channel.
    private func tuneFromList(_ channel: LiveChannel) {
        listHighlight = channel.id
        restartChannelListTimer()
        guard channel.id != liveChannelID else { return }
        zapTask?.cancel()
        zapTarget = nil
        AppLog.detail(.player, "channel list tunes \(channel.id)")
        app.play(channel)
        if let entry = app.neighbor(of: channel.id, categoryId: channel.categoryId, offset: 0) {
            showOSD(entry, autoHide: true)
        }
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        let live = engine.isLive
        let shift = event.modifierFlags.contains(.shift)
        if showsChannelList, handleChannelListKey(event.keyCode) {
            showControls()
            return true
        }
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
            case "l" where live: toggleChannelList()
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

    /// Why live playback stalls, when Fernsy has evidence for it: no network on the Mac, or the
    /// channel's connection delivers too slowly, nothing, or is being replaced. Nil while the
    /// connection is healthy (the plain spinner then).
    private var stallCard: (symbol: String, title: String, detail: String)? {
        if !app.isNetworkAvailable {
            return ("wifi.slash", String(localized: "No internet connection"),
                    String(localized: "Fernsy continues as soon as the network is back."))
        }
        switch engine.connectionHealth {
        case .ok:
            return nil
        case .reconnecting(loadBalancer: true):
            return ("tortoise", String(localized: "The channel arrives too slowly from the provider"),
                    String(localized: "Fernsy is switching to another server of the provider …"))
        case .slow, .silent, .reconnecting:
            return ("tortoise", String(localized: "The channel arrives too slowly from the provider"),
                    String(localized: "Fernsy is waiting for data …"))
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch engine.status {
        case .loading where !engine.isReconnecting:
            VStack(spacing: 18) {
                if let id = liveChannelID, let channel = app.channel(id) {
                    LogoTile(url: channel.icon, name: channel.displayName, width: 150)
                }
                ProgressView().controlSize(.large).tint(.white)
                Text("Loading \(app.nowPlaying?.title ?? "")…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .allowsHitTesting(false)
        case .loading, .buffering:
            if engine.isReconnecting || engine.reconnectAttempt > 0 {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.regular).tint(.white)
                    Text("Reconnecting…").font(.callout.weight(.semibold))
                    if engine.reconnectAttempt > 0 {
                        Text("Attempt \(engine.reconnectAttempt) of \(PlayerEngine.maxReconnectAttempts)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 26).padding(.vertical, 18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
            } else if stallCardVisible, let card = stallCard {
                VStack(spacing: 10) {
                    Image(systemName: card.symbol).font(.system(size: 22, weight: .semibold))
                    Text(card.title).font(.callout.weight(.semibold))
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text(card.detail)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26).padding(.vertical, 18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
            } else {
                ProgressView().controlSize(.large).tint(.white).allowsHitTesting(false)
            }
        case .failed(let message):
            let offline = message == PlayerError.offline.localizedDescription
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x1A1300))
                    .frame(width: 38, height: 38)
                    .background(Theme.warning, in: Circle())
                Text(offline ? String(localized: "Channel is offline at the provider") : message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if offline {
                    Text("\(app.nowPlaying?.title ?? "") is not sending a picture right now. This is the provider, not your connection.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Button("Try Again") {
                        if let item = loadedItem {
                            if item.isLive { app.retuneForPlayer() }
                            play(item)
                        }
                    }
                    if loadedItem?.isLive == true {
                        Button("Next Channel  ↓") { zap(1) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 400)
            .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .environment(\.colorScheme, .dark)
        case .ended:
            Button {
                engine.setPaused(false)
            } label: {
                Label("Play Again", systemImage: "arrow.counterclockwise")
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

/// TV-style channel banner: number, logo, name, what is on now and what follows.
struct ChannelOSD: View {
    @EnvironmentObject private var app: AppModel
    let channel: LiveChannel
    let number: Int
    /// Still choosing (key presses continue); the channel is not tuned yet.
    let isPending: Bool
    @State private var now: EPGEntry?
    @State private var next: EPGEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text(verbatim: "\(number)")
                    .font(.system(size: 26, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(minWidth: 50, alignment: .leading)
                LogoTile(url: channel.icon, name: channel.displayName, width: 66)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        TaggedName(name: channel.parsed, font: .title3, weight: .bold)
                        if isPending {
                            ProgressView().controlSize(.small).tint(.white).opacity(0.7)
                        }
                    }
                    if let now {
                        Text(verbatim: "\(now.title) · \(now.start.formatted(date: .omitted, time: .shortened))–\(now.end.formatted(date: .omitted, time: .shortened))")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            if let now {
                ProgressBar(value: now.progress, tint: .white, height: 4)
            }
            HStack {
                if let next {
                    Text("Next \(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)")
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    keyCap("↑")
                    keyCap("↓")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 440, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 25, y: 18)
        .environment(\.colorScheme, .dark)
        .task(id: channel.id) {
            now = nil
            next = nil
            // Short debounce: no EPG request for channels that are only skipped past.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let entries = (try? await app.client?.shortEPG(channel.id, limit: 3)) ?? []
            now = entries.first { $0.start <= Date() && $0.end > Date() } ?? entries.first
            next = entries.first { $0.start >= (now?.end ?? Date()) }
        }
    }

    private func keyCap(_ key: String) -> some View {
        Text(verbatim: key)
            .padding(.horizontal, 5)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
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
            .help(waiting ? String(localized: "The channel is currently sending no audio. Sound will resume automatically.")
                          : String(localized: "This channel has no audio track."))
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
            if let method = stats.playMethod { row("Playback", method) }
            row("Container", stats.container)
            row("Video", stats.videoCodec)
            row("Resolution", stats.resolution)
            row("Frame rate", stats.frameRate > 0 ? String(format: "%.2f fps", stats.frameRate) : "–")
            row("Decoder", stats.decoder)
            row("Pixel format", stats.pixelFormat)
            row("Dynamic range", stats.dynamicRange)
            row("Deinterlacing", stats.deinterlace.isEmpty ? "–" : stats.deinterlace)
            row("Audio", stats.audio)
            row("Bit rate", String(format: "%.1f Mbit/s", stats.bitrateMbps))
            Divider().overlay(.white.opacity(0.25)).gridCellColumns(2)
            row("Buffer", bufferText)
            if let stored = stats.timeshiftStored {
                row("Timeshift buffer", String(localized: "\(formatTime(stored)) stored"))
            }
            row("Connection", stats.connectTime > 0 ? String(format: String(localized: "%.0f ms to first response"), stats.connectTime * 1000) : "")
            row("Startup", stats.startupTime > 0 ? String(format: String(localized: "%.1f s to first frame"), stats.startupTime) : "")
            row("Reconnects", reconnectText)
            row("Rebuffers", "\(stats.rebuffers)")
            row("Dropped", String(localized: "\(stats.droppedFrames) frames") + (stats.duplicatesDropped > 0 ? " · " + String(localized: "\(stats.duplicatesDropped) duplicates") : ""))
            if stats.decodeFailures > 0 {
                row("Decode errors", String(localized: "\(stats.decodeFailures) frames"))
            }
        }
    }

    private var bufferText: String {
        if let ahead = stats.timeshiftAhead {
            let disk = ahead >= 60 ? formatTime(ahead) : String(format: "%.1f s", ahead)
            return String(format: "%.1f s", stats.bufferSeconds) + " + " + String(localized: "Disk \(disk)")
        }
        let network = Double(stats.networkBufferBytes)
        let networkText = network >= 1_000_000 ? String(format: "%.1f MB", network / 1_000_000) : String(format: "%.0f KB", network / 1000)
        // Network bytes in seconds at the average data rate, when it is known.
        let rate = history.averageMbps * 125_000
        let networkSeconds = rate > 0 ? String(format: " ≈ %.1f s", network / rate) : ""
        return String(format: "%.1f s", stats.bufferSeconds) + " + " + String(localized: "network \(networkText)\(networkSeconds)")
    }

    private var reconnectText: String {
        var parts = [String(localized: "\(stats.seamlessReconnects) seamless")]
        if stats.restarts > 0 { parts.append(String(localized: "\(stats.restarts) restarts")) }
        var text = parts.joined(separator: " · ")
        if stats.isReconnecting {
            text += " · " + String(localized: "connecting…")
        } else if let at = stats.lastReconnectAt {
            let ago = Int(Date().timeIntervalSince(at))
            let when = ago < 60 ? String(localized: "\(ago) s ago") : String(localized: "\(ago / 60) min ago")
            text += "\n" + String(localized: "last \(when): \(stats.lastReconnectReason ?? "")")
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
                Text("Buffer, last 2 min").foregroundStyle(.white.opacity(0.6))
                Spacer()
                legend(Self.playerColor, "Player")
                legend(Self.networkColor, isTimeshift ? "Disk" : "Net")
            }
            chart.frame(width: 300, height: 90)
            HStack(spacing: 10) {
                legend(.orange, "Reconnect")
                legend(.purple, "Restart")
                legend(.red, "Rebuffer")
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
                AreaMark(x: .value("Time", x), y: .value("Seconds", sample.player), stacking: .standard)
                    .foregroundStyle(by: .value("Share", "Player"))
                AreaMark(x: .value("Time", x), y: .value("Seconds", min(sample.network, max(0, Self.cap - sample.player))), stacking: .standard)
                    .foregroundStyle(by: .value("Share", "Net"))
                ForEach(Array(sample.events.enumerated()), id: \.offset) { _, event in
                    RuleMark(x: .value("Time", x))
                        .foregroundStyle(Self.color(for: event))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            RuleMark(y: .value("Threshold", 4))
                .foregroundStyle(.white.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartForegroundStyleScale(["Player": Self.playerColor.opacity(0.8), "Net": Self.networkColor.opacity(0.7)])
        .chartLegend(.hidden)
        .chartXScale(domain: -BufferHistory.window...0)
        .chartYScale(domain: 0...max(10, (peak / 5).rounded(.up) * 5))
        .chartXAxis {
            AxisMarks(values: [-120, -90, -60, -30, 0]) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(seconds == 0 ? "now" : "\(Int(seconds)) s")
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
    @State private var remaining = Int(JellyfinPlayback.autoplayDelay)

    var body: some View {
        if let next = playback.nextEpisode, !playback.autoplayCancelled {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next Up").font(.headline).foregroundStyle(.secondary)
                Text(label(next)).font(.title2.weight(.semibold)).lineLimit(2)
                HStack {
                    Button("Play Now (\(remaining))") { play(next) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { playback.cancelAutoplay() }
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
            .task(id: playback.autoplayAt) {
                // The countdown belongs to the playback, so the assistant sees the same one.
                guard let deadline = playback.autoplayAt else { return }
                while !Task.isCancelled {
                    remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
                    if remaining == 0 { play(next); return }
                    try? await Task.sleep(for: .milliseconds(250))
                }
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
