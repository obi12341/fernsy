import AVFoundation
import Combine
import SwiftUI

/// Position/duration live in their own object so that 10 Hz clock updates only
/// re-render the transport bar, not the whole player.
final class PlaybackProgress: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var buffered: Double = 0
    /// Timeshift: buffer time range that can be played, and the clock time of `position`.
    @Published var liveStart: Double = 0
    @Published var liveEnd: Double = 0
    @Published var wallClock: Date?
    /// Timeshift: playback follows the live stream (not paused or rewound since). Measured
    /// distance to the newest data is no good for this: providers deliver in bursts.
    @Published var followsLive = true

    /// Seconds behind live (0 while following live).
    var behindLive: Double { followsLive ? 0 : max(0, liveEnd - position - PlayerEngine.liveLead) }
}

/// Buffer level over time for the info overlay. Separate object so the once-per-second
/// samples only re-render the chart.
final class BufferHistory: ObservableObject {
    enum Event { case reconnect, restart, rebuffer }

    struct Sample: Identifiable {
        let id: Int
        let time: Date
        /// Demuxed and waiting in the player.
        let player: Double
        /// Received but not yet demuxed, converted at the average data rate.
        let network: Double
        let events: [Event]
    }

    static let window: TimeInterval = 120

    @Published private(set) var samples: [Sample] = []
    /// Average over the last 30 s; single seconds are useless for bursty channels.
    @Published private(set) var averageMbps = 0.0

    private var nextID = 0
    private var rates: [Double] = []
    private var previous: PlaybackStats?

    func reset() {
        samples = []
        rates = []
        averageMbps = 0
        previous = nil
    }

    /// The restart count is passed separately: it lives in the engine, not in the session.
    /// `disk`: timeshift, seconds stored ahead of the player (instead of network bytes).
    func record(_ stats: PlaybackStats, disk: Double? = nil) {
        rates.append(stats.bitrateMbps)
        if rates.count > 30 { rates.removeFirst(rates.count - 30) }
        averageMbps = rates.reduce(0, +) / Double(rates.count)

        var events: [Event] = []
        if let previous {
            // Session counters restart from zero after a full restart.
            if stats.restarts > previous.restarts { events.append(.restart) }
            else if stats.seamlessReconnects > previous.seamlessReconnects { events.append(.reconnect) }
            if stats.rebuffers > previous.rebuffers { events.append(.rebuffer) }
        }
        previous = stats

        let rate = averageMbps * 125_000
        let network = disk ?? (rate > 0 ? Double(stats.networkBufferBytes) / rate : 0)
        let now = Date()
        samples.append(Sample(id: nextID, time: now, player: stats.bufferSeconds, network: network, events: events))
        nextID += 1
        if let first = samples.firstIndex(where: { now.timeIntervalSince($0.time) <= Self.window }), first > 0 {
            samples.removeFirst(first)
        }
    }
}

/// Owns the renderers and the current PlaybackSession; main-thread API for the UI.
final class PlayerEngine: ObservableObject {
    enum Status: Equatable {
        case idle, loading, playing, paused, buffering, ended
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var media: MediaInfo?
    @Published private(set) var videoSize: CGSize = .zero
    @Published private(set) var stats = PlaybackStats()
    @Published private(set) var subtitleText: String?
    @Published private(set) var isPaused = false
    @Published private(set) var isReconnecting = false
    /// The source is currently not delivering audio for the selected track.
    @Published private(set) var isAudioMissing = false
    @Published var volume: Float {
        didSet {
            audioRenderer.volume = volume
            UserDefaults.standard.set(volume, forKey: "player.volume")
        }
    }
    @Published var isMuted = false {
        didSet { audioRenderer.isMuted = isMuted }
    }

    let progress = PlaybackProgress()
    let bufferHistory = BufferHistory()
    let displayLayer = AVSampleBufferDisplayLayer()

    private let audioRenderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let controlQueue = DispatchQueue(label: "player.control", qos: .userInitiated)
    private var session: PlaybackSession? // controlQueue only

    private var generation = 0
    private var currentURL: URL?
    private var currentIsLive = false
    /// Live from a tuner's timeshift buffer (seekable) instead of straight from the network.
    @Published private(set) var isTimeshift = false
    private var tuner: LiveTuner?
    private var tunerState: AnyCancellable?
    static var liveLead: Double { PlaybackSession.liveLead }
    private var reconnectAttempts = 0
    /// Full restarts since the last user-initiated load.
    private var restarts = 0
    private var startedAt: Date?
    private var cues: [SubtitleCue] = []
    private var activity: NSObjectProtocol?
    private var flushObserver: NSObjectProtocol?

    init() {
        let stored = UserDefaults.standard.object(forKey: "player.volume") as? Float
        volume = stored ?? 1.0

        displayLayer.videoGravity = .resize // the view sizes the layer to the exact display aspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
        displayLayer.backgroundColor = NSColor.black.cgColor
        audioRenderer.volume = volume

        synchronizer.addRenderer(displayLayer.sampleBufferRenderer)
        synchronizer.addRenderer(audioRenderer)
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false

        flushObserver = NotificationCenter.default.addObserver(
            forName: .AVSampleBufferAudioRendererWasFlushedAutomatically, object: audioRenderer, queue: .main
        ) { [weak self] _ in
            // Output device changed: refill audio from the current position.
            guard let self, !self.currentIsLive || self.isTimeshift, self.status == .playing || self.status == .paused else { return }
            self.seek(to: self.progress.position)
        }
    }

    deinit {
        if let flushObserver { NotificationCenter.default.removeObserver(flushObserver) }
        let s = session
        controlQueue.async { s?.stop() }
    }

    var isLive: Bool { currentIsLive }

    // MARK: Control

    func load(url: URL, isLive: Bool, startAt: Double = 0) {
        detachTuner()
        reconnectAttempts = 0
        restarts = 0
        bufferHistory.reset()
        start(url: url, mode: .network(isLive: isLive), startAt: startAt)
    }

    /// A recording file; `isGrowing` while it is still being written.
    func load(file url: URL, isGrowing: @escaping () -> Bool, startAt: Double = 0) {
        detachTuner()
        reconnectAttempts = 0
        restarts = 0
        bufferHistory.reset()
        start(url: url, mode: .file(FileByteSource(url: url, isGrowing: isGrowing)), startAt: startAt)
    }

    /// Live TV through the channel's tuner: starts at the live edge of its timeshift buffer.
    func load(tuner: LiveTuner) {
        detachTuner()
        reconnectAttempts = 0
        restarts = 0
        bufferHistory.reset()
        self.tuner = tuner
        isTimeshift = true
        progress.followsLive = true
        let (publisher, state) = MainActor.assumeIsolated { (tuner.$state, tuner.state) }
        tunerState = publisher.sink { [weak self] state in
            self?.tunerChanged(state)
        }
        guard state != .unsupported else { return }
        start(url: tuner.url, mode: .buffer(tuner.buffer), startAt: -1)
    }

    private func detachTuner() {
        tunerState = nil
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
        generation += 1
        let gen = generation
        currentURL = url
        let isLive: Bool
        switch mode {
        case .network(let live): isLive = live
        case .buffer, .tuner: isLive = true
        case .file: isLive = false
        }
        currentIsLive = isLive
        status = .loading
        media = nil
        stats = PlaybackStats()
        stats.restarts = restarts
        cues = []
        subtitleText = nil
        isPaused = false
        isAudioMissing = false
        startedAt = nil
        progress.position = max(0, startAt)
        progress.duration = 0
        progress.buffered = 0
        beginActivity()

        let videoRenderer = displayLayer.sampleBufferRenderer
        let audioRenderer = audioRenderer
        let synchronizer = synchronizer
        controlQueue.async { [weak self] in
            guard let self else { return }
            // Single-connection accounts: the old stream must be fully closed first.
            self.session?.stop()
            self.session = nil
            synchronizer.setRate(0, time: .zero)
            videoRenderer.flush()
            audioRenderer.flush()
            let session = PlaybackSession(
                url: url, mode: mode, startPosition: startAt,
                videoRenderer: videoRenderer, audioRenderer: audioRenderer, synchronizer: synchronizer
            ) { [weak self] event in
                self?.handle(event, generation: gen)
            }
            self.session = session
            session.start()
        }
    }

    func stop() {
        detachTuner()
        generation += 1
        status = .idle
        isAudioMissing = false
        media = nil
        currentURL = nil
        endActivity()
        let videoRenderer = displayLayer.sampleBufferRenderer
        let audioRenderer = audioRenderer
        let synchronizer = synchronizer
        controlQueue.async { [weak self] in
            self?.session?.stop()
            self?.session = nil
            synchronizer.setRate(0, time: .zero)
            videoRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            audioRenderer.flush()
        }
    }

    func togglePause() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
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

    func seek(to position: Double) {
        guard !currentIsLive || isTimeshift, status != .idle else { return }
        let target: Double
        if isTimeshift, let buffer = tuner?.buffer {
            let oldest = buffer.oldest?.time ?? 0
            let live = (buffer.newest?.time ?? 0) - Self.liveLead
            target = min(max(oldest, position), max(oldest, live))
            progress.followsLive = position >= live - 1
        } else {
            let duration = progress.duration
            target = duration > 0 ? min(max(0, position), duration - 1) : max(0, position)
        }
        progress.position = target
        cues = []
        subtitleText = nil
        if status == .ended { status = .buffering }
        let paused = isPaused
        controlQueue.async { [weak self] in
            self?.session?.seek(to: target)
            self?.session?.setPaused(paused)
        }
    }

    func seek(by delta: Double) {
        seek(to: progress.position + delta)
    }

    /// Following live but far behind it (started while the server was still sending its
    /// backlog, or after stalls): jump to the live edge, as live TV would.
    private var lagSince: Date?

    private func catchUpIfLagging(_ position: Double) {
        guard progress.followsLive, !isPaused, status == .playing,
              progress.liveEnd - position > Self.liveLead + 12 else {
            lagSince = nil
            return
        }
        if lagSince == nil { lagSince = Date() }
        guard let since = lagSince, Date().timeIntervalSince(since) > 4 else { return }
        lagSince = nil
        #if DEBUG
        debugLog("[player] \(String(format: "%.1f", progress.liveEnd - position)) s behind live, catching up")
        #endif
        goLive()
    }

    /// Timeshift: back to the live edge.
    func goLive() {
        guard isTimeshift, let newest = tuner?.buffer.newest?.time else { return }
        if isPaused { setPaused(false) }
        seek(to: newest)
    }

    func selectAudio(_ track: MediaTrack) {
        media?.selectedAudio = track.id
        controlQueue.async { [weak self] in self?.session?.selectAudio(track.id) }
    }

    func selectSubtitle(_ track: MediaTrack?) {
        media?.selectedSubtitle = track?.id
        cues = []
        subtitleText = nil
        controlQueue.async { [weak self] in self?.session?.selectSubtitle(track?.id) }
    }

    // MARK: Events

    private func handle(_ event: PlaybackSession.Event, generation gen: Int) {
        guard gen == generation else { return }
        #if DEBUG
        switch event {
        case .position, .subtitle: break
        case .stats(let s):
            debugLog("[player] stats \(s.videoCodec) \(s.resolution) \(String(format: "%.2f", s.frameRate))fps decoder=\(s.decoder) fmt=\(s.pixelFormat) deint=\(s.deinterlace) \(s.dynamicRange) audio=\(s.audio) buffer=\(String(format: "%.1f", s.bufferSeconds))s rate=\(String(format: "%.1f", s.bitrateMbps))Mbit drops=\(s.droppedFrames) audioAhead=\(String(format: "%.2f", s.audioAhead))s net=\(s.networkBufferBytes / 1024)KB reconnects=\(s.seamlessReconnects) dups=\(s.duplicatesDropped) rebuffers=\(s.rebuffers) pos=\(String(format: "%.1f", progress.position))")
        default:
            debugLog("[player] \(event)")
        }
        #endif
        switch event {
        case .opened(let info):
            media = info
            progress.duration = info.duration ?? 0
        case .videoSize(let size):
            videoSize = size
        case .started:
            status = isPaused ? .paused : .playing
            isReconnecting = false
            startedAt = Date()
        case .buffering(let flag):
            if flag { status = .buffering } else { status = isPaused ? .paused : .playing }
        case .position(let position, let buffered):
            progress.position = position
            progress.buffered = buffered
            if isTimeshift, let tuner {
                let buffer = tuner.buffer
                progress.liveStart = buffer.oldest?.time ?? 0
                progress.liveEnd = buffer.newest?.time ?? position
                progress.wallClock = buffer.wallTime(of: position)
                tuner.reportPlaybackAhead(max(0, progress.liveEnd - position))
                catchUpIfLagging(position)
            }
            updateSubtitle(at: position)
            if let startedAt, Date().timeIntervalSince(startedAt) > 20 { reconnectAttempts = 0 }
        case .stats(var s):
            s.restarts = restarts
            if isTimeshift {
                s.timeshiftStored = max(0, progress.liveEnd - progress.liveStart)
                s.timeshiftAhead = max(0, progress.liveEnd - progress.position - s.bufferSeconds)
            }
            stats = s
            bufferHistory.record(s, disk: s.timeshiftAhead)
        case .subtitle(let cue):
            cues.append(cue)
            if cues.count > 400 { cues.removeFirst(cues.count - 400) }
        case .clearSubtitles:
            cues = []
            subtitleText = nil
        case .audioGap(let missing):
            isAudioMissing = missing
        case .ended:
            if currentIsLive {
                reconnect(reason: String(localized: "Stream beendet"))
            } else {
                status = .ended
                endActivity()
            }
        case .failed(let message, let retry):
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
            return
        }
        let active = cues.last { $0.start <= position && position < $0.end && !$0.text.isEmpty }
        if active?.text != subtitleText { subtitleText = active?.text }
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

#if DEBUG
private let debugStart = Date()

func debugLog(_ message: String) {
    let t = String(format: "%7.2f", Date().timeIntervalSince(debugStart))
    FileHandle.standardError.write(Data(("\(t) " + message + "\n").utf8))
}
#endif
