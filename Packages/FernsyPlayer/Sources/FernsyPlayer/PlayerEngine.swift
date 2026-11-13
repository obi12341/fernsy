import AVFoundation
import CFFShim
import Combine
import FernsyCore
import SwiftUI

/// Owns the renderers and the current PlaybackSession; main-thread API for the UI.
public final class PlayerEngine: ObservableObject {
    public enum Status: Equatable {
        case idle, loading, playing, paused, buffering, ended
        case failed(String)
    }

    @Published public private(set) var status: Status = .idle {
        didSet {
            // An item that fails or ends before its first frame must not leave the loading picture running.
            switch status {
            case .failed, .ended: loadingCard.stop()
            default: break
            }
            guard status != oldValue else { return }
            noteUnhealthyStall()
            switch status {
            case .failed(let message):
                logStallEnd("failed")
                AppLog.error(.player, "playback failed: \(message)")
            case .ended: AppLog.info(.player, "playback ended")
            default: break
            }
        }
    }
    @Published public private(set) var media: MediaInfo?
    private var nextStatsLog = Date.distantPast
    /// When the picture stopped for lack of data (after the start), for the log.
    private var stallStartedAt: Date?
    @Published public private(set) var videoSize: CGSize = .zero
    /// What the picture is (frame rate, dynamic range), for the Apple TV's display mode; nil when stopped.
    @Published public private(set) var displayFormat: DisplayFormat?
    /// The Apple TV holds the first start of each item here while the TV switches its mode.
    public let startHold = StartHold()
    @Published public private(set) var stats = PlaybackStats()
    @Published public private(set) var subtitleText: String?
    /// The bitmap subtitle (PGS, VobSub, DVB) to draw now.
    @Published public private(set) var subtitleBitmap: BitmapCue?
    /// Set by a controller (Jellyfin) for the current item.
    public private(set) var external: ExternalPlayback?
    /// Cues supplied by a controller (external subtitle file); the stream's own are ignored.
    private var externalCues: [SubtitleCue]?
    private var bitmapCues: [BitmapCue] = []
    private var hasStarted = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var isReconnecting = false
    /// The source is currently not delivering audio for the selected track.
    @Published public private(set) var isAudioMissing = false
    @Published public var volume: Float {
        didSet {
            audioRenderer.volume = volume
            #if DEBUG
            return
            #else
            UserDefaults.standard.set(volume, forKey: "player.volume")
            #endif
        }
    }
    @Published public var isMuted = false {
        didSet { audioRenderer.isMuted = isMuted }
    }

    public let progress = PlaybackProgress()
    public let bufferHistory = BufferHistory()
    public let displayLayer: AVSampleBufferDisplayLayer

    /// While Picture in Picture runs: the loading picture shown until a new item's first frame.
    public private(set) lazy var loadingCard = PictureInPictureLoadingCard(sink: videoSink)
    public let lastPicture = LastPicture()
    #if DEBUG
    private var debugOpenedItems = 0
    #endif
    private var audioRenderer: AVSampleBufferAudioRenderer
    private var audioEvents: Task<Void, Never>?
    /// Failed audio renderers replaced for the current item (at most three).
    private var audioReplacements = 0
    let synchronizer: AVSampleBufferRenderSynchronizer
    /// The renderers' receivers (macOS 27): every enqueue and flush goes through them.
    public let videoSink: VideoSink
    private let audioSink: AudioSink
    private var sinkEvents: [Task<Void, Never>] = []
    /// Recent automatic video recoveries (rate limit, give up after three in 30 s).
    private var recoveries: [Date] = []
    private var lastDecodeFailures = 0
    private let controlQueue = DispatchQueue(label: "player.control", qos: .userInitiated)
    private var session: PlaybackSession? // controlQueue only

    private var generation = 0
    private var currentURL: URL?
    /// Position of the last reload after an early end: a second early end there gives up.
    private var earlyEndRecoveredAt: Double?
    private var currentIsLive = false
    /// Live from a tuner's timeshift buffer (seekable) instead of straight from the network.
    @Published public private(set) var isTimeshift = false
    private var tuner: LiveTuner?
    private var tunerState: AnyCancellable?
    private var tunerHealth: AnyCancellable?
    private var tunerRecovery: AnyCancellable?
    /// Live: how the tuner's connection delivers (the status card names the provider only
    /// when it is slow, silent or being replaced).
    /// The current item streams from the IPTV provider (not Jellyfin, a file or Fernsy Cloud),
    /// so "IPTV only with VPN" applies to it.
    public private(set) var contactsProvider = false
    @Published public private(set) var connectionHealth: HTTPByteSource.Health = .ok {
        didSet { noteUnhealthyStall() }
    }
    /// When the picture last waited while the connection was slow, silent or being replaced:
    /// the note after a server switch only follows a stall the user saw.
    private var unhealthyStallAt = Date.distantPast
    /// Live: another provider server ended a stall; shown for a few seconds.
    @Published public private(set) var showsServerSwitchNote = false
    private var serverSwitchNoteHide: DispatchWorkItem?
    public static var liveLead: Double { PlaybackSession.liveLead }
    private var reconnectAttempts = 0 {
        didSet { if reconnectAttempt != reconnectAttempts { reconnectAttempt = reconnectAttempts } }
    }
    /// The player's own restart of the stream (shown as "Versuch n von 8"); 0 when none runs.
    @Published public private(set) var reconnectAttempt = 0
    public static let maxReconnectAttempts = 8
    /// Full restarts since the last user-initiated load.
    private var restarts = 0
    private var startedAt: Date?
    private var cues: [SubtitleCue] = []
    private var activity: NSObjectProtocol?

    public init() {
        let stored = UserDefaults.standard.object(forKey: "player.volume") as? Float
        volume = stored ?? 1.0
        let displayLayer = AVSampleBufferDisplayLayer()
        let audioRenderer = AVSampleBufferAudioRenderer()
        let synchronizer = AVSampleBufferRenderSynchronizer()
        self.displayLayer = displayLayer
        self.audioRenderer = audioRenderer
        self.synchronizer = synchronizer
        videoSink = VideoSink(receiver: synchronizer.sampleBufferReceiver(adding: displayLayer.sampleBufferRenderer))
        nonisolated(unsafe) let renderer = audioRenderer
        audioSink = AudioSink(receiver: synchronizer.sampleBufferReceiver(adding: audioRenderer), status: { renderer.status })

        displayLayer.videoGravity = .resize // the view sizes the layer to the exact display aspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
        displayLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        audioRenderer.volume = volume
        // AirPods and other headphones spatialise 5.1/7.1 as well as stereo.
        audioRenderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        _ = AudioOutput.shared // sets the audio session's category
        #if DEBUG
        // Test runs are silent unless asked for: the user may be watching in the installed app.
        if ProcessInfo.processInfo.environment["IPTV_SOUND"] != "1" {
            isMuted = true
            audioRenderer.isMuted = true
            AppLog.info(.player, "debug build starts muted (IPTV_SOUND=1 for sound)")
        }
        #endif

        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false

        // Problems reported after enqueuing stopped (e.g. while paused); during playback the
        // enqueue results report them (session events).
        let engine = WeakEngine(self)
        sinkEvents.append(videoSink.observeEvents(
            needsFlush: { reason in DispatchQueue.main.async { engine.value?.recoverVideo(reason) } },
            decodeFailures: { count in DispatchQueue.main.async { AppLog.warning(.player, "\(count) video frames could not be decoded") } }))
        observeAudioEvents()
    }

    private func observeAudioEvents() {
        let engine = WeakEngine(self)
        audioEvents?.cancel()
        audioEvents = audioSink.observeEvents { DispatchQueue.main.async { engine.value?.refillAudio() } }
    }

    /// A failed audio renderer stays failed, even after a flush: a new one takes its place in
    /// the synchronizer and the sound is refilled.
    private func replaceAudioRenderer() {
        guard audioRenderer.status == .failed else { return }
        guard audioReplacements < 3 else {
            AppLog.error(.player, "audio renderer failed again (\(String(describing: audioRenderer.error))), playing without sound")
            return
        }
        audioReplacements += 1
        AppLog.warning(.player, "audio renderer failed (\(String(describing: audioRenderer.error))), replacing it")
        synchronizer.removeRenderer(audioRenderer, at: synchronizer.currentTime(), completionHandler: nil)
        let renderer = AVSampleBufferAudioRenderer()
        renderer.volume = volume
        renderer.isMuted = isMuted
        renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        audioRenderer = renderer
        nonisolated(unsafe) let r = renderer
        audioSink.replace(receiver: synchronizer.sampleBufferReceiver(adding: renderer), status: { r.status })
        observeAudioEvents()
        refillAudio()
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak renderer] in
            debugLog("[test] replacement audio renderer: status \(renderer?.status.rawValue ?? -1) (1 = rendering)")
        }
        #endif
    }

    deinit {
        sinkEvents.forEach { $0.cancel() }
        audioEvents?.cancel()
        let s = session
        controlQueue.async { s?.stop() }
    }

    public var isLive: Bool { currentIsLive }

    // MARK: Control

    /// Language rules for the next load (settings, or the series' remembered choice).
    public var trackPreferences = TrackPreferences.settings
    /// Tracks for the current stream; the user's pick replaces it so restarts keep it.
    private var trackRequest: TrackRequest = .preferences(TrackPreferences())

    public func load(url: URL, isLive: Bool, startAt: Double = 0, external: ExternalPlayback? = nil) {
        trackRequest = external?.tracks ?? .preferences(trackPreferences)
        detachTuner()
        self.external = external
        externalCues = nil
        reconnectAttempts = 0
        restarts = 0
        recoveries = []
        bufferHistory.reset()
        start(url: url, mode: .network(isLive: isLive), startAt: startAt)
    }

    /// A network film or episode that "ends" more than 60 s before its known duration was cut
    /// off (e.g. an interrupted download), not watched to the end: load it again at the position
    /// once, then report a failure – never `.ended`, which media servers take as "watched".
    private func recoverFromEarlyEnd() -> Bool {
        let position = progress.position, duration = progress.duration
        guard duration > 0, position < duration - 60, let url = currentURL, !url.isFileURL else { return false }
        if let last = earlyEndRecoveredAt, abs(position - last) < 30 {
            status = .failed(String(localized: "Playback interrupted", bundle: .module))
            endActivity()
            return true
        }
        earlyEndRecoveredAt = position
        AppLog.warning(.player, "ended at \(Int(position)) s of \(Int(duration)) s – reloading there")
        if let restart = external?.restartAt {
            restart(position)
        } else {
            start(url: url, mode: .network(isLive: false), startAt: position)
        }
        return true
    }

    /// A recording file; `isGrowing` while it is still being written.
    public func load(file url: URL, isGrowing: @escaping () -> Bool, startAt: Double = 0) {
        trackRequest = .preferences(trackPreferences)
        detachTuner()
        external = nil
        externalCues = nil
        reconnectAttempts = 0
        restarts = 0
        recoveries = []
        bufferHistory.reset()
        start(url: url, mode: .file(FileByteSource(url: url, isGrowing: isGrowing)), startAt: startAt)
    }

    /// A Fernsy Cloud recording, streamed and decrypted by `source` (add-recording-cloud).
    public func load(cloud source: CloudByteSource, startAt: Double = 0) {
        trackRequest = .preferences(trackPreferences)
        detachTuner()
        external = nil
        externalCues = nil
        reconnectAttempts = 0
        restarts = 0
        recoveries = []
        bufferHistory.reset()
        start(url: CloudByteSource.itemURL(source.recordingId), mode: .file(source), startAt: startAt)
    }

    /// Live TV through the channel's tuner: starts at the live edge of its timeshift buffer.
    public func load(tuner: LiveTuner) {
        trackRequest = .preferences(trackPreferences)
        detachTuner()
        external = nil
        externalCues = nil
        reconnectAttempts = 0
        restarts = 0
        recoveries = []
        bufferHistory.reset()
        self.tuner = tuner
        isTimeshift = true
        progress.followsLive = true
        lagBaseline = nil
        lagWindowStart = nil
        recentLag.removeAll()
        let (publisher, state) = MainActor.assumeIsolated { (tuner.$state, tuner.state) }
        tunerState = publisher.sink { [weak self] state in
            self?.tunerChanged(state)
        }
        let (health, recovered) = MainActor.assumeIsolated { (tuner.$health, tuner.$recoveredAt) }
        tunerHealth = health.sink { [weak self] health in
            guard let self, self.connectionHealth != health else { return }
            #if DEBUG
            debugLog("[health] \(health)")
            #endif
            self.connectionHealth = health
        }
        tunerRecovery = recovered.dropFirst().compactMap { $0 }.sink { [weak self] _ in
            self?.showServerSwitchNote()
        }
        guard state != .unsupported else { return }
        start(url: tuner.url, mode: .buffer(tuner.buffer), startAt: -1)
    }

    private func noteUnhealthyStall() {
        if status == .buffering && connectionHealth != .ok { unhealthyStallAt = Date() }
    }

    private func showServerSwitchNote() {
        guard Date().timeIntervalSince(unhealthyStallAt) < 60 else { return }
        AppLog.info(.player, "note: another provider server delivers smoothly again")
        serverSwitchNoteHide?.cancel()
        showsServerSwitchNote = true
        let hide = DispatchWorkItem { [weak self] in self?.showsServerSwitchNote = false }
        serverSwitchNoteHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: hide)
    }

    private func detachTuner() {
        tunerState = nil
        tunerHealth = nil
        tunerRecovery = nil
        connectionHealth = .ok
        serverSwitchNoteHide?.cancel()
        showsServerSwitchNote = false
        tuner = nil
        isTimeshift = false
        progress.liveStart = 0
        progress.liveEnd = 0
        progress.wallClock = nil
        progress.followsLive = true
    }

    private func tunerChanged(_ state: LiveTuner.State) {
        guard let tuner else { return }
        switch state {
        case .unsupported:
            // The tuner has let the connection go: play directly, without timeshift.
            let url = tuner.url
            detachTuner()
            start(url: url, mode: .network(isLive: true), startAt: 0)
        case .failed(let message):
            status = .failed(message)
            isReconnecting = false
            endActivity()
        case .reconnecting:
            isReconnecting = true
        case .running:
            isReconnecting = false
        default:
            break
        }
    }

    private func start(url: URL, mode: PlaybackSession.Mode, startAt: Double) {
        // A restart of the same stream continues the freeze; another item ends it.
        if url != currentURL { logStallEnd("switched to another item") }
        generation += 1
        let gen = generation
        currentURL = url
        let isLive: Bool
        switch mode {
        case .network(let live):
            isLive = live
            contactsProvider = external?.contactsProvider ?? true
        case .buffer, .tuner:
            isLive = true
            contactsProvider = true
        case .file:
            isLive = false
            contactsProvider = false
        }
        currentIsLive = isLive
        audioReplacements = 0
        AudioOutput.shared.prepare()
        status = .loading
        media = nil
        stats = PlaybackStats()
        stats.restarts = restarts
        cues = []
        subtitleText = nil
        isPaused = false
        isAudioMissing = false
        startedAt = nil
        progress.position = max(0, startAt) + (external?.timelineOffset ?? 0)
        progress.duration = external?.duration ?? 0
        hasStarted = false
        displayFormat = nil
        startHold.arm()
        bitmapCues = []
        subtitleBitmap = nil
        progress.buffered = 0
        beginActivity()
        lastDecodeFailures = 0 // each session counts from zero

        let videoSink = videoSink
        let audioSink = audioSink
        let tracks = trackRequest
        let guarded = external?.contactsProvider ?? true
        let synchronizer = synchronizer
        let loadingCard = loadingCard
        let lastPicture = lastPicture
        controlQueue.async { [weak self] in
            guard let self else { return }
            // Single-connection accounts: the old stream must be fully closed first.
            self.session?.stop()
            self.session = nil
            synchronizer.setRate(0, time: .zero)
            videoSink.flush()
            audioSink.flush()
            let session = PlaybackSession(
                url: url, mode: mode, startPosition: startAt, tracks: tracks, guarded: guarded,
                videoSink: videoSink, audioSink: audioSink, synchronizer: synchronizer
            ) { [weak self] event in
                self?.handle(event, generation: gen)
            }
            session.beforeFirstVideo = { loadingCard.stop() }
            session.lastPicture = lastPicture
            session.startHold = startHold
            self.session = session
            #if DEBUG
            // IPTV_TESTSLOWSTART=<s>: a slow provider – the new item starts that much later.
            if let delay = ProcessInfo.processInfo.environment["IPTV_TESTSLOWSTART"].flatMap(Double.init) {
                Thread.sleep(forTimeInterval: delay)
            }
            #endif
            session.start()
        }
    }

    public func stop() {
        logStallEnd("stopped")
        loadingCard.stop()
        lastPicture.set(nil)
        earlyEndRecoveredAt = nil
        detachTuner()
        external = nil
        externalCues = nil
        generation += 1
        displayFormat = nil
        status = .idle
        isAudioMissing = false
        media = nil
        currentURL = nil
        endActivity()
        let videoSink = videoSink
        let audioSink = audioSink
        let synchronizer = synchronizer
        controlQueue.async { [weak self] in
            self?.session?.stop()
            self?.session = nil
            synchronizer.setRate(0, time: .zero)
            videoSink.flushRemovingImage()
            audioSink.flush()
        }
    }

    public func togglePause() {
        setPaused(!isPaused)
    }

    /// For Picture in Picture: live streams show as live, and the time range is expressed on
    /// the display layer's clock (the synchronizer's).
    public var isLiveStream: Bool { currentIsLive }
    public var clockTime: Double { synchronizer.currentTime().seconds }

    public func setPaused(_ paused: Bool) {
        guard status != .idle else { return }
        if status == .ended && !paused {
            seek(to: 0)
        }
        isPaused = paused
        if paused && isTimeshift { progress.followsLive = false }
        if status == .playing || status == .paused {
            status = paused ? .paused : .playing
        }
        controlQueue.async { [weak self] in self?.session?.setPaused(paused) }
    }

    public func seek(to position: Double) {
        guard !currentIsLive || isTimeshift, status != .idle else { return }
        let target: Double
        if isTimeshift, let buffer = tuner?.buffer {
            let oldest = buffer.oldest?.time ?? 0
            let live = (buffer.newest?.time ?? 0) - Self.liveLead
            target = min(max(oldest, position), max(oldest, live))
            progress.followsLive = position >= live - 1
            if progress.followsLive { resetLagBaseline() }
        } else {
            let duration = progress.duration
            target = duration > 0 ? min(max(0, position), duration - 1) : max(0, position)
        }
        if let restart = external?.restartAt {
            // Not seekable (progressive transcode): the controller starts a new stream there.
            progress.position = target
            bitmapCues = []
            subtitleBitmap = nil
            restart(target)
            return
        }
        progress.position = target
        cues = []
        subtitleText = nil
        if status == .ended { status = .buffering }
        bitmapCues = []
        subtitleBitmap = nil
        let paused = isPaused
        let offset = external?.timelineOffset ?? 0
        controlQueue.async { [weak self] in
            self?.session?.seek(to: target - offset)
            self?.session?.setPaused(paused)
        }
    }

    /// Timeshift: the clock time of a buffer position, read from the buffer itself (the published
    /// `progress.wallClock` follows a seek only a moment later).
    public func wallTime(of position: Double) -> Date? {
        guard isTimeshift else { return nil }
        return tuner?.buffer.wallTime(of: position)
    }

    public func seek(by delta: Double) {
        seek(to: progress.position + delta)
    }

    /// Distance to the newest data that following live settled at: providers send a backlog
    /// burst on connect, which is played rather than skipped (no jump on channel switch).
    private var lagBaseline: Double?
    /// First start of the current tune; the baseline is measured during the 15 s after it.
    private var lagWindowStart: Date?
    /// Recent distances to the newest data. Providers deliver in segments, so the distance
    /// swings by seconds; the lowest value of the last 6 s is the steady one.
    private var recentLag: [(time: Date, lag: Double)] = []
    #if DEBUG
    private var loggedBaseline = true
    #endif

    /// Never jumps: playback that falls clearly further behind than it settled (stalls) leaves
    /// the live state, so the badge shows the time behind; "Live" is the user's choice.
    private func leaveLiveIfLagging(_ position: Double) {
        guard progress.followsLive, !isPaused, status == .playing, let windowStart = lagWindowStart else {
            recentLag.removeAll()
            return
        }
        let now = Date()
        recentLag.append((now, progress.liveEnd - position))
        recentLag.removeAll { now.timeIntervalSince($0.time) > 6 }
        guard let first = recentLag.first, now.timeIntervalSince(first.time) > 5,
              let steady = recentLag.map(\.lag).min() else { return }
        if now.timeIntervalSince(windowStart) < 15 {
            lagBaseline = max(lagBaseline ?? Self.liveLead, steady)
            #if DEBUG
            loggedBaseline = false
            #endif
            return
        }
        #if DEBUG
        if !loggedBaseline {
            loggedBaseline = true
            AppLog.detail(.player, "live start settled \(String(format: "%.1f", lagBaseline ?? Self.liveLead)) s behind the newest data")
        }
        #endif
        guard steady > max(lagBaseline ?? Self.liveLead, Self.liveLead) + 12 else { return }
        AppLog.info(.player, "\(String(format: "%.1f", steady)) s behind live (settled at \(String(format: "%.1f", lagBaseline ?? Self.liveLead)) s), leaving live")
        progress.followsLive = false
        recentLag.removeAll()
    }

    /// At the live edge again (the user's "Live" or a seek to the edge): measure from there.
    private func resetLagBaseline() {
        lagBaseline = Self.liveLead
        lagWindowStart = .distantPast
        recentLag.removeAll()
    }

    /// Timeshift: back to the live edge.
    public func goLive() {
        guard isTimeshift, let newest = tuner?.buffer.newest?.time else { return }
        if isPaused { setPaused(false) }
        seek(to: newest)
    }

    public func selectAudio(_ track: MediaTrack) {
        if let handler = external?.selectAudio, handler(track) { return }
        media?.selectedAudio = track.id
        trackRequest = .explicit(audio: track.id, subtitle: media?.selectedSubtitle)
        controlQueue.async { [weak self] in self?.session?.selectAudio(track.id) }
    }

    public func selectSubtitle(_ track: MediaTrack?) {
        if let handler = external?.selectSubtitle, handler(track) { return }
        media?.selectedSubtitle = track?.id
        trackRequest = .explicit(audio: media?.selectedAudio, subtitle: track?.id)
        externalCues = nil
        cues = []
        subtitleText = nil
        bitmapCues = []
        subtitleBitmap = nil
        controlQueue.async { [weak self] in self?.session?.selectSubtitle(track?.id) }
    }

    /// A controller shows subtitles from a file (track id chosen by the controller); the stream's
    /// own subtitle track is switched off.
    public func showExternalSubtitles(_ cues: [SubtitleCue], trackId: Int32) {
        media?.selectedSubtitle = trackId
        externalCues = cues.sorted { $0.start < $1.start }
        self.cues = []
        subtitleText = nil
        bitmapCues = []
        subtitleBitmap = nil
        controlQueue.async { [weak self] in self?.session?.selectSubtitle(nil) }
    }

    /// Subtitles off, without touching the stream (a controller's own subtitles).
    public func clearSubtitleSelection() {
        media?.selectedSubtitle = nil
        externalCues = nil
        cues = []
        subtitleText = nil
    }

    /// A controller adds tracks the stream does not contain (external files) to the menus.
    public func addSubtitleTracks(_ tracks: [MediaTrack]) {
        guard var info = media else { return }
        info.subtitleTracks += tracks.filter { t in !info.subtitleTracks.contains { $0.id == t.id } }
        media = info
    }

    /// A controller replaces the track menus (transcodes offer the source's tracks).
    public func setTracks(audio: [MediaTrack], subtitles: [MediaTrack], selectedAudio: Int32?, selectedSubtitle: Int32?) {
        guard var info = media else { return }
        info.audioTracks = audio
        info.subtitleTracks = subtitles
        info.selectedAudio = selectedAudio
        info.selectedSubtitle = selectedSubtitle
        media = info
    }

    /// Logs how long the picture stood still (the user-visible part of a stall).
    private func logStallEnd(_ outcome: String? = nil) {
        guard let since = stallStartedAt else { return }
        stallStartedAt = nil
        let seconds = Date().timeIntervalSince(since)
        let text = String(format: "stalled for %.1f s", seconds) + (outcome.map { ", then \($0)" } ?? "")
        if seconds >= 3 { AppLog.warning(.player, text) } else { AppLog.info(.player, text) }
    }

    // MARK: Events

    private func handle(_ event: PlaybackSession.Event, generation gen: Int) {
        guard gen == generation else { return }
        switch event {
        case .position, .subtitle, .clearSubtitles: break
        case .bitmapSubtitle(let cue): AppLog.detail(.player, "bitmap subtitle \(cue.pieces.count) pictures at \(String(format: "%.1f", cue.start)) s")
        case .stats(let s):
            // Every ten seconds is enough to follow a stream's health.
            guard Date() >= nextStatsLog else { break }
            nextStatsLog = Date().addingTimeInterval(10)
            if s.decodeFailures > lastDecodeFailures {
                AppLog.warning(.player, "\(s.decodeFailures - lastDecodeFailures) video frames could not be decoded")
                lastDecodeFailures = s.decodeFailures
            }
            AppLog.detail(.player, "stats \(s.videoCodec) \(s.resolution) \(String(format: "%.2f", s.frameRate))fps decoder=\(s.decoder) fmt=\(s.pixelFormat) deint=\(s.deinterlace) \(s.dynamicRange) audio=\(s.audio) buffer=\(String(format: "%.1f", s.bufferSeconds))s rate=\(String(format: "%.1f", s.bitrateMbps))Mbit drops=\(s.droppedFrames) audioAhead=\(String(format: "%.2f", s.audioAhead))s net=\(s.networkBufferBytes / 1024)KB reconnects=\(s.seamlessReconnects) dups=\(s.duplicatesDropped) rebuffers=\(s.rebuffers) pos=\(String(format: "%.1f", progress.position))")
        case .failed(let message, let retry):
            // The outcome (reconnect or failure) is logged where it is decided.
            AppLog.detail(.player, "session failed: \(message) (retry: \(retry))")
        default:
            AppLog.detail(.player, "\(event)")
        }
        switch event {
        case .opened(var info):
            #if DEBUG
            // IPTV_TESTNOVIDEO=1: every item after the first counts as one without picture (radio).
            if ProcessInfo.processInfo.environment["IPTV_TESTNOVIDEO"] != nil, debugOpenedItems > 0 { info.hasVideo = false }
            debugOpenedItems += 1
            #endif
            if !info.hasVideo { loadingCard.stop() }
            media = info
            progress.duration = external?.duration ?? info.duration ?? 0
            external?.onOpened?()
        case .videoSize(let size):
            videoSize = size
        case .displayFormat(let format):
            displayFormat = format
        case .started:
            logStallEnd()
            hasStarted = true
            status = isPaused ? .paused : .playing
            isReconnecting = false
            startedAt = Date()
            if isTimeshift && lagWindowStart == nil {
                lagWindowStart = Date()
                #if DEBUG
                scheduleStallTest()
                #endif
            }
        case .buffering(let flag):
            if flag { status = .buffering } else { status = isPaused ? .paused : .playing }
            if flag && hasStarted && stallStartedAt == nil {
                stallStartedAt = Date()
            } else if !flag {
                logStallEnd()
            }
        case .position(let streamPosition, let streamBuffered):
            let offset = external?.timelineOffset ?? 0
            let position = streamPosition + offset
            progress.position = position
            progress.buffered = streamBuffered + offset
            if isTimeshift, let tuner {
                let buffer = tuner.buffer
                progress.liveStart = buffer.oldest?.time ?? 0
                progress.liveEnd = buffer.newest?.time ?? position
                progress.wallClock = buffer.wallTime(of: position)
                tuner.reportPlaybackAhead(max(0, progress.liveEnd - position))
                leaveLiveIfLagging(position)
            }
            updateSubtitle(at: position)
            if let startedAt, Date().timeIntervalSince(startedAt) > 20 { reconnectAttempts = 0 }
        case .stats(var s):
            s.restarts = restarts
            s.playMethod = external?.methodLabel
            s.outputChannels = AudioOutput.shared.channels
            s.renderingMode = AudioOutput.shared.renderingMode
            if isTimeshift {
                s.timeshiftStored = max(0, progress.liveEnd - progress.liveStart)
                s.timeshiftAhead = max(0, progress.liveEnd - progress.position - s.bufferSeconds)
            }
            stats = s
            bufferHistory.record(s, disk: s.timeshiftAhead)
        case .subtitle(var cue):
            let offset = external?.timelineOffset ?? 0
            cue = SubtitleCue(start: cue.start + offset, end: cue.end + offset, text: cue.text)
            cues.append(cue)
            if cues.count > 400 { cues.removeFirst(cues.count - 400) }
        case .bitmapSubtitle(var cue):
            let offset = external?.timelineOffset ?? 0
            cue.start += offset
            cue.end += offset
            // A cue without an end lasts until the next one (PGS display sets).
            if let last = bitmapCues.indices.last, bitmapCues[last].end > cue.start { bitmapCues[last].end = cue.start }
            if !cue.images.isEmpty { bitmapCues.append(cue) }
            if bitmapCues.count > 200 { bitmapCues.removeFirst(bitmapCues.count - 200) }
        case .clearSubtitles:
            cues = []
            subtitleText = nil
            bitmapCues = []
            subtitleBitmap = nil
        case .audioGap(let missing):
            isAudioMissing = missing
        case .decoderNeedsFlush(let reason):
            recoverVideo(reason)
        case .audioNeedsRefill:
            refillAudio()
        case .audioRendererFailed:
            replaceAudioRenderer()
        case .ended:
            if currentIsLive {
                reconnect(reason: String(localized: "Stream ended", bundle: .module))
            } else if !recoverFromEarlyEnd() {
                status = .ended
                endActivity()
            }
        case .failed(let message, let retry):
            if !hasStarted, let fallback = external?.onFailedBeforeStart, fallback(message) {
                return
            }
            if hasStarted, let recover = external?.onFailedAfterStart, recover(message) {
                return
            }
            if isTimeshift, let tuner {
                // The buffer session broke (e.g. paused past the buffer's end): the tuner itself
                // reports its own failures. Pick up again where it can.
                let active = MainActor.assumeIsolated { tuner.isActive }
                guard active, reconnectAttempts < 8 else {
                    if active { status = .failed(message); endActivity() }
                    return
                }
                reconnectAttempts += 1
                let position = max(progress.position, tuner.buffer.oldest?.time ?? 0)
                let gen = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, gen == self.generation, let tuner = self.tuner else { return }
                    self.start(url: tuner.url, mode: .buffer(tuner.buffer), startAt: position)
                }
            } else if currentIsLive && retry {
                reconnect(reason: message)
            } else {
                status = .failed(message)
                endActivity()
            }
        }
    }

    /// The video decoder needs a flush and a key frame: resume at the current position, which
    /// flushes and restarts decoding there (live: from the buffer, or by reconnecting).
    private func recoverVideo(_ reason: String) {
        guard status == .playing || status == .paused || status == .buffering, currentURL != nil else { return }
        let now = Date()
        recoveries.removeAll { now.timeIntervalSince($0) > 30 }
        if let last = recoveries.last, now.timeIntervalSince(last) < 2 { return }
        guard recoveries.count < 3 else {
            AppLog.error(.player, "video decoder keeps failing (\(reason)), giving up")
            halt()
            status = .failed(String(localized: "The picture could not be restored.", bundle: .module))
            return
        }
        recoveries.append(now)
        AppLog.warning(.player, "video decoder needs a restart (\(reason)), resuming at \(Int(progress.position)) s")
        if isTimeshift && progress.followsLive {
            // Watching live: stay live.
            goLive()
        } else if !currentIsLive || isTimeshift {
            seek(to: progress.position)
        } else {
            reconnect(reason: String(localized: "Decoder restarted", bundle: .module))
        }
    }

    /// Stops the session but keeps the last frame on screen (under a status card).
    private func halt() {
        generation += 1
        endActivity()
        let synchronizer = synchronizer
        let audioSink = audioSink
        controlQueue.async { [weak self] in
            self?.session?.stop()
            self?.session = nil
            synchronizer.setRate(0, time: .zero)
            audioSink.flush()
        }
    }

    /// The audio output changed (or its renderer failed): refill audio from the current position.
    private func refillAudio() {
        guard !currentIsLive || isTimeshift, status == .playing || status == .paused else { return }
        AppLog.info(.player, "audio output changed, refilling at \(Int(progress.position)) s")
        seek(to: progress.position)
    }

    /// A controller gave up recovering (e.g. the Jellyfin session could not be renewed).
    public func reportFailure(_ message: String) {
        status = .failed(message)
        isReconnecting = false
        endActivity()
    }

    private func reconnect(reason: String) {
        guard let url = currentURL else { return }
        guard reconnectAttempts < 8 else {
            status = .failed(reason)
            isReconnecting = false
            endActivity()
            return
        }
        reconnectAttempts += 1
        restarts += 1
        AppLog.warning(.player, "reconnecting (attempt \(reconnectAttempts)): \(reason)")
        isReconnecting = true
        status = .buffering
        let gen = generation
        let delay = min(5.0, 0.5 * Double(reconnectAttempts))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.start(url: url, mode: .network(isLive: true), startAt: 0)
        }
    }

    private func updateSubtitle(at position: Double) {
        guard media?.selectedSubtitle != nil else {
            if subtitleText != nil { subtitleText = nil }
            if subtitleBitmap != nil { subtitleBitmap = nil }
            return
        }
        // Every cue active now (two speakers at once), in order of appearance.
        let source = externalCues ?? cues
        let active = source.filter { $0.start <= position && position < $0.end && !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
        var seen = Set<String>()
        let text = active.map(\.text).filter { seen.insert($0).inserted }.joined(separator: "\n")
        let shown = text.isEmpty ? nil : text
        if shown != subtitleText { subtitleText = shown }
        let bitmap = bitmapCues.last { $0.start <= position && position < $0.end }
        if bitmap?.id != subtitleBitmap?.id { subtitleBitmap = bitmap }
    }

    // Keep the process out of App Nap / timer coalescing while playing.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled], reason: "Video playback")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}

/// A weak engine reference the receivers' event tasks can carry; it is only read on the main queue.
private final class WeakEngine: @unchecked Sendable {
    weak var value: PlayerEngine?
    init(_ value: PlayerEngine) { self.value = value }
}
