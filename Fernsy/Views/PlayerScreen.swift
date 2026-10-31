import AppIntents
import Charts
import Combine
import FernsyCore
import FernsyPlayer
import SwiftUI

struct PlayerScreen: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    @StateObject var engine = PlayerEngine()

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    /// Sliders being dragged right now: the controls stay up meanwhile (the slider tracks the
    /// mouse, so no hover or move events count as activity).
    @State private var activeDrags = 0
    @State var showInfo = false
    @State var pip: PictureInPicture?
    @State private var pipPossible = false
    @State private var pipStage = PictureInPictureStage()
    @State private var epg: [EPGEntry] = []
    @State private var loadedItem: PlayItem?
    /// Live playback has been buffering for a second (short stalls stay a plain spinner).
    @State private var stallCardVisible = false
    @EnvironmentObject private var jellyfin: JellyfinStore
    /// The Jellyfin item playing (direct/transcode, progress reports, next episode).
    @State private var jellyfinPlayback: JellyfinPlayback?
    /// The archive playback of a past show (catch-up), kept while it plays.
    @State private var archivePlayback: ArchivePlayback?
    @State var isFullScreen = false

    // Zapping: the OSD follows key presses immediately, tuning waits until they stop,
    // so skipping through channels does not open a connection for each one.
    @State private var osd: (channel: LiveChannel, number: Int)?
    @State var zapTarget: (channel: LiveChannel, number: Int)?
    @State private var zapTask: Task<Void, Never>?
    @State private var osdHideTask: Task<Void, Never>?
    // The channel list over the picture (live TV, L).
    @State var showsChannelList = false
    @State var listCategory = allCategoryID
    @State var listHighlight: Int?
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
            runDebugHooks()
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
        if case .jellyfin = item.kind { stopJellyfin() }
        let archive = app.startPlayback(item, on: engine, isCurrent: { loadedItem == item }) { playback in
            jellyfinPlayback = playback
            app.jellyfinPlayback = playback
        }
        if let archive { archivePlayback = archive }
    }

    // MARK: Track choice

    func pick(audio track: MediaTrack) {
        let subtitle = engine.media.flatMap { m in m.subtitleTracks.first { $0.id == m.selectedSubtitle } }
        engine.selectAudio(track)
        remember(audio: track, subtitle: subtitle)
    }

    func pick(subtitle track: MediaTrack?) {
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

    func showControls() {
        showControls(autoHide: true)
    }

    func showControls(autoHide: Bool) {
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
    var playerWindow: NSWindow? {
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

    func toggleFullScreen() {
        guard let window = playerWindow else { return }
        // SwiftUI treats single-instance `Window` scenes as auxiliary and keeps resetting the
        // collection behaviour; auxiliary windows cannot get their own full-screen space.
        window.collectionBehavior.remove([.fullScreenAuxiliary, .auxiliary])
        window.collectionBehavior.insert([.fullScreenPrimary, .primary])
        window.toggleFullScreen(nil)
    }

    // MARK: Zapping

    func zap(_ offset: Int) {
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

    func toggleChannelList() {
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
    func restartChannelListTimer() {
        listHideTask?.cancel()
        listHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, showsChannelList else { return }
            closeChannelList()
        }
    }

    /// Keys while the list is open: ↑/↓ and Page Up/Down move the highlight, Return tunes,
    /// L and Esc close it. Other keys keep their meaning.
    func handleChannelListKey(_ keyCode: UInt16) -> Bool {
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

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for child in subviews {
            if let match = child.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
