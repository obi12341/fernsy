import AVFoundation
import Combine
import SwiftUI

/// Position/duration live in their own object so that 10 Hz clock updates only
/// re-render the transport bar, not the whole player.
final class PlaybackProgress: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var buffered: Double = 0
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
    func record(_ stats: PlaybackStats) {
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
        let network = rate > 0 ? Double(stats.networkBufferBytes) / rate : 0
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
            guard let self, !self.currentIsLive, self.status == .playing || self.status == .paused else { return }
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
        reconnectAttempts = 0
        restarts = 0
        bufferHistory.reset()
        start(url: url, isLive: isLive, startAt: startAt)
    }

    private func start(url: URL, isLive: Bool, startAt: Double) {
        generation += 1
        let gen = generation
        currentURL = url
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
        progress.position = startAt
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
                url: url, isLive: isLive, startPosition: startAt,
                videoRenderer: videoRenderer, audioRenderer: audioRenderer, synchronizer: synchronizer
            ) { [weak self] event in
                self?.handle(event, generation: gen)
            }
            self.session = session
            session.start()
        }
    }

    func stop() {
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
        if status == .playing || status == .paused {
            status = paused ? .paused : .playing
        }
        controlQueue.async { [weak self] in self?.session?.setPaused(paused) }
    }

    func seek(to position: Double) {
        guard !currentIsLive, status != .idle else { return }
        let duration = progress.duration
        let target = duration > 0 ? min(max(0, position), duration - 1) : max(0, position)
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
            updateSubtitle(at: position)
            if let startedAt, Date().timeIntervalSince(startedAt) > 20 { reconnectAttempts = 0 }
        case .stats(var s):
            s.restarts = restarts
            stats = s
            bufferHistory.record(s)
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
            if currentIsLive && retry {
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
            self.start(url: url, isLive: true, startAt: 0)
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
