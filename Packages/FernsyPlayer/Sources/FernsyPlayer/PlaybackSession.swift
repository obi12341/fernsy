import AVFoundation
import CFFShim
import CoreMedia
import CoreVideo
import FernsyCore

extension CMTime {
    init(sec: Double) { self = CMTime(seconds: sec, preferredTimescale: 90_000) }
}

/// One playback of one URL: demuxer thread, video and audio decoder threads and
/// a monitor that drives the shared AVSampleBufferRenderSynchronizer clock.
///
/// Pipeline:
///   HTTPByteSource → libavformat → PacketQueue
///   video: libavcodec (VideoToolbox) → [yadif_videotoolbox] → CVPixelBuffer → AVSampleBufferVideoRenderer
///   audio: libavcodec → swresample (float32) → AVSampleBufferAudioRenderer
///
/// Live channels normally run as two sessions: a headless `.tuner` session receives the
/// network stream and hands cleaned packets to a TimeshiftWriter, and a `.buffer` session
/// plays the resulting timeshift buffer (seekable).
public final class PlaybackSession {
    public enum Mode {
        /// Straight from HTTP: VOD, or live without timeshift.
        case network(isLive: Bool)
        /// Live ingest without decoding; packets go to the output.
        case tuner(TunerOutput)
        /// A tuned channel's timeshift buffer. Start position -1 = live edge.
        case buffer(TimeshiftBuffer)
        /// A recording on disk or in Fernsy Cloud: seekable, not live.
        case file(ByteSource)
    }

    public enum Event {
        case opened(MediaInfo)
        case videoSize(CGSize)
        /// What the display layer shows, on the first frame and when it changes (tvos-match-content).
        case displayFormat(DisplayFormat)
        case started
        case buffering(Bool)
        case position(Double, buffered: Double)
        case stats(PlaybackStats)
        case subtitle(SubtitleCue)
        case bitmapSubtitle(BitmapCue)
        case clearSubtitles
        /// The selected audio track currently delivers nothing (source-side gap).
        case audioGap(Bool)
        /// The video decoder needs a flush and a key frame (sleep/wake, display change, broken data).
        case decoderNeedsFlush(String)
        /// The audio renderer suggests a refill (output device changed).
        case audioNeedsRefill
        /// The audio renderer failed (a bitstream the system cannot play, broken PCM): it needs
        /// replacing, as a flush does not reset it.
        case audioRendererFailed
        case ended
        /// `retry`: a live reconnect may help (network drop), as opposed to e.g. an offline channel.
        case failed(String, retry: Bool)
    }

    private let url: URL
    private let mode: Mode
    /// Network live stream (reconnect junctions, duplicate removal, audio rescue).
    let isLive: Bool
    /// Plays a live timeline (live buffering rules), from the network or the buffer.
    let liveTimeline: Bool
    let tunerOutput: TunerOutput?
    private let timeshift: TimeshiftBuffer?
    /// Tuner: streams handed to the output (video, every audio track, DVB subtitles).
    private var keptStreams: Set<Int32> = []
    private let startPosition: Double
    /// The renderers' receivers; nil for the headless tuner, which never outputs anything.
    let videoSink: VideoSink?
    let audioSink: AudioSink?
    let sync: AVSampleBufferRenderSynchronizer
    private let onEvent: (Event) -> Void

    let source: ByteSource
    private let sourceBox: SourceBox
    var fmt: UnsafeMutablePointer<AVFormatContext>?
    private var pb: UnsafeMutablePointer<AVIOContext>?
    private var subCtx: UnsafeMutablePointer<AVCodecContext>?
    private let trackRequest: TrackRequest

    let videoQ = PacketQueue()
    let audioQ = PacketQueue()
    private let group = DispatchGroup()
    var monitor: DispatchSourceTimer?

    // MARK: Shared state (guarded by `lock`)

    let lock = NSLock()
    var stopped = false
    var serial = 0
    var videoIndex: Int32 = -1
    var audioIndex: Int32 = -1
    private var subtitleIndex: Int32 = -1
    var hasVideo = false
    var hasAudio = false
    var timeOffset = 0.0

    var prerolling = true
    var prerollTarget: Double?
    var prerollStartedAt = Date()
    var startTime: Double?
    var firstAudioPTS: Double?
    /// The first audio sample of this preroll lies after the video start (late-starting audio).
    var audioStartsLater = false
    var userPaused = false
    var buffering = false
    var eof = false
    var endedSent = false
    var videoDrained = false
    var audioDrained = false
    var videoEnqueuedUntil = -Double.infinity
    var audioEnqueuedUntil = -Double.infinity
    var videoDemuxedUntil = -Double.infinity
    var audioDemuxedUntil = -Double.infinity

    private var pendingSeek: Double?
    private var pendingAudio: Int32?
    private var pendingSubtitle: Int32??

    // Stats (guarded by `lock`)
    var stats = PlaybackStats()
    var framesPresented = 0
    var lateDrops = 0
    /// Frames the video renderer could not decode (counted from enqueue results).
    var decodeFailures = 0
    /// One recovery or refill request per flush (the output threads only).
    var videoRecoveryRequested = false
    var audioRefillRequested = false
    /// The audio renderer failed and the engine was told (audio thread only).
    var audioFailureReported = false
    var lastStatsAt = Date()
    var lastStatsFrames = 0
    var lastStatsBytes: Int64 = 0
    var lastDisplaySize = CGSize.zero
    let createdAt = Date()
    var rebuffers = 0
    var duplicatesDropped = 0

    // Live reconnect junctions (demux thread only). Every new connection starts with a replay
    // of the server's buffer, possibly from another backend with an unrelated clock. Packets
    // are compared on the output timeline (stream time minus the connection's cut): what was already
    // played is dropped, so playback continues seamlessly instead of jumping back.
    var lastOut: [Int32: Double] = [:]
    var history = ContentHistory(capacity: 8192)

    struct Connection {
        /// First byte of this connection in the source's byte stream.
        let start: Int64
        /// Seconds subtracted from its stream time: absorbs clock differences between
        /// backends and content a reconnect skipped.
        var cut: Double
        /// Whether `cut` is known (from a content match or the first new packet).
        var decided: Bool
        /// New packets held back while waiting for a content match.
        var alignWait = 0
    }

    /// Every connection so far. FFmpeg emits packets well after their bytes were read, so
    /// after several quick reconnects packets of older connections still arrive; each is
    /// placed with its own connection's cut. Quick reconnects may each land on another backend.
    var connections = [Connection(start: 0, cut: 0, decided: true)]
    /// Per stream: connection of the latest packet carrying a byte position (packets split
    /// out of one PES report none and inherit it).
    var packetConnection: [Int32: Int] = [:]
    /// Per stream: the newest connection in which it has moved past the replayed part.
    var rejoinedConnection: [Int32: Int] = [:]
    var needKeyframe = false
    // TSAudioTap frames on the output timeline. The tap sees bytes as they are read, ahead of
    // the demuxer, so its frames always belong to the newest connection.
    var tapConnection = 0
    var tapRejoining = false
    var tapNextOut: Double?
    var lastTapOut: Double?
    #if DEBUG
    let debugClockSkew = ProcessInfo.processInfo.environment["IPTV_TESTCLOCK"].flatMap(Double.init) ?? 0
    #endif

    /// Runs on the video thread right before the first video frame goes to the renderer (the
    /// engine stops anything else feeding the renderer there, e.g. the PiP loading picture).
    public var beforeFirstVideo: (() -> Void)?
    /// Receives every video frame that goes to the renderer.
    public var lastPicture: LastPicture?
    /// Holds the first start while the Apple TV switches its display mode.
    public var startHold: StartHold?
    var sentVideo = false

    public init(url: URL, mode: Mode, startPosition: Double, tracks: TrackRequest = .preferences(TrackPreferences()),
         videoSink: VideoSink?, audioSink: AudioSink?,
         synchronizer: AVSampleBufferRenderSynchronizer, onEvent: @escaping (Event) -> Void) {
        self.url = url
        self.trackRequest = tracks
        self.mode = mode
        self.startPosition = startPosition
        self.videoSink = videoSink
        self.audioSink = audioSink
        self.sync = synchronizer
        self.onEvent = onEvent
        switch mode {
        case .network(let live):
            isLive = live
            liveTimeline = live
            tunerOutput = nil
            timeshift = nil
            source = HTTPByteSource(url: url, isLive: live)
        case .tuner(let output):
            isLive = true
            liveTimeline = true
            tunerOutput = output
            timeshift = nil
            let http = HTTPByteSource(url: url, isLive: true)
            http.contentClock = { [weak output] in output?.contentTime }
            source = http
        case .buffer(let buffer):
            isLive = false
            liveTimeline = true
            tunerOutput = nil
            timeshift = buffer
            source = BufferByteSource(buffer: buffer)
        case .file(let file):
            isLive = false
            liveTimeline = false
            tunerOutput = nil
            timeshift = nil
            source = file
        }
        sourceBox = SourceBox(source)
    }

    /// Headless live ingest for a tuner: no renderers are ever used.
    public convenience init(tunerURL: URL, output: TunerOutput, onEvent: @escaping (Event) -> Void) {
        self.init(url: tunerURL, mode: .tuner(output), startPosition: 0,
                  videoSink: nil, audioSink: nil,
                  synchronizer: AVSampleBufferRenderSynchronizer(), onEvent: onEvent)
    }

    var isTuner: Bool { tunerOutput != nil }

    /// Network counters of the source (for a tuner: its connection).
    public var networkStats: (HTTPByteSource.NetStats, Int64) {
        (source.netStats, source.totalBytesReceived)
    }

    /// Tuner: the connection's health and a recovery via another server (watchdog queue).
    public func observeConnection(health: @escaping (HTTPByteSource.Health) -> Void, recovered: @escaping () -> Void) {
        guard let http = source as? HTTPByteSource else { return }
        http.onHealth = health
        http.onRecovered = recovered
    }

    /// Tuner: how much the slowest consumer still has ahead (stall detection).
    public func reportPlaybackAhead(_ seconds: Double) {
        source.reportPlaybackAhead(seconds)
    }

    deinit {
        freeFormat()
    }

    // Stored state of the extensions (PlaybackSession+*.swift).
    var tickCount = 0
    var audioGapSince: Date?
    var audioGapShown = false

    // MARK: Public control (thread-safe)

    public func start() {
        group.enter()
        let thread = Thread { [self] in demuxMain() }
        thread.name = "player.demux"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Blocks until every thread has exited. Never call from a session thread.
    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        source.cancel()
        videoQ.abort()
        audioQ.abort()
        monitor?.cancel()
        group.wait()
        freeFormat()
    }

    public func setPaused(_ paused: Bool) {
        lock.lock()
        defer { lock.unlock() }
        userPaused = paused
        guard !prerolling else { return }
        sync.rate = (paused || buffering) ? 0 : 1
    }

    /// `position` is in display time (0 = start of media).
    public func seek(to position: Double) {
        guard !isLive else { return }
        lock.lock()
        pendingSeek = max(0, position) + timeOffset
        lock.unlock()
    }

    public func selectAudio(_ index: Int32) {
        lock.lock()
        pendingAudio = index
        lock.unlock()
    }

    public func selectSubtitle(_ index: Int32?) {
        lock.lock()
        pendingSubtitle = .some(index)
        lock.unlock()
    }

    var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    func emit(_ event: Event) {
        let handler = onEvent
        DispatchQueue.main.async { handler(event) }
    }

    // MARK: - Demuxer

    private func demuxMain() {
        defer { group.leave() }
        if let timeshift, !timeshift.waitForContent(seconds: 0, timeout: 25, cancelled: { isStopped }) {
            if !isStopped { emit(.failed(String(localized: "No data from the channel", bundle: .module), retry: true)) }
            return
        }
        do {
            #if DEBUG
            if !PlayerError.debugAllows(url) { throw PlayerError.debugRealProvider }
            #endif
            try openInput()
            try selectStreams()
        } catch {
            if !isStopped {
                let retry: Bool
                switch error {
                case PlayerError.offline, PlayerError.unsupported, PlayerError.debugRealProvider: retry = false
                default: retry = true
                }
                emit(.failed(error.localizedDescription, retry: retry))
            }
            return
        }
        guard let fmt else { return }

        if isLive {
            source.onRejoin = { [weak self] offset in self?.rejoin(at: offset) }
        }
        #if DEBUG
        scheduleNetworkTest()
        #endif

        if !isTuner {
            if hasVideo { spawn("player.video", qos: .userInteractive) { [self] in videoMain() } }
            if hasAudio { spawn("player.audio", qos: .userInteractive) { [self] in audioMain() } }
            startMonitor()
        }

        if let timeshift {
            // Live edge: a few seconds back, so the decoders have data to work with.
            let oldest = timeshift.oldest?.time ?? 0
            let target = startPosition >= 0 ? startPosition : max(oldest, (timeshift.newest?.time ?? 0) - Self.liveLead)
            performSeek(to: max(oldest, target) + timeOffset)
        } else if startPosition > 1 && !isLive {
            performSeek(to: startPosition + timeOffset)
        } else {
            lock.lock()
            prerollStartedAt = Date()
            lock.unlock()
        }

        guard let pkt = av_packet_alloc() else { return }
        defer {
            var p: UnsafeMutablePointer<AVPacket>? = pkt
            av_packet_free(&p)
        }

        let maxBytes = liveTimeline ? 48 << 20 : 160 << 20
        let targetAhead = liveTimeline ? 8.0 : 20.0

        while !isStopped {
            lock.lock()
            let seekTarget = pendingSeek
            pendingSeek = nil
            let audioSwitch = pendingAudio
            pendingAudio = nil
            let subtitleSwitch = pendingSubtitle
            pendingSubtitle = nil
            let atEOF = eof
            lock.unlock()

            if audioSwitch != nil || subtitleSwitch != nil {
                applyTrackChanges(audio: audioSwitch, subtitle: subtitleSwitch)
                continue
            }
            if let seekTarget {
                performSeek(to: seekTarget)
                continue
            }
            if atEOF {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }

            // Back-pressure: enough buffered for every active stream, or too many bytes.
            // A tuner reads whatever the network delivers.
            if isTuner {
                let ret = av_read_frame(fmt, pkt)
                if ret < 0 {
                    if !isStopped { emit(.failed(String(localized: "Stream interrupted", bundle: .module), retry: true)) }
                    break
                }
                route(pkt, fmt: fmt)
                continue
            }
            let now = sync.currentTime().seconds
            lock.lock()
            let videoAhead = hasVideo ? videoDemuxedUntil - now : .infinity
            let audioAhead = hasAudio ? audioDemuxedUntil - now : .infinity
            let isPrerolling = prerolling
            lock.unlock()
            let bytes = videoQ.byteCount + audioQ.byteCount
            if bytes > maxBytes || (!isPrerolling && min(videoAhead, audioAhead) > targetAhead) {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }

            let ret = av_read_frame(fmt, pkt)
            if ret < 0 {
                if isStopped { break }
                if liveTimeline {
                    emit(.failed(String(localized: "Stream interrupted", bundle: .module), retry: true))
                    break
                }
                if ret != ffs_error_eof() && fmt.pointee.pb?.pointee.eof_reached == 0 {
                    // Network error mid-file: surface it rather than pretending we ended.
                    emit(.failed(source.failureMessage ?? String(localized: "Connection lost", bundle: .module), retry: false))
                    break
                }
                markEOF()
                continue
            }
            route(pkt, fmt: fmt)
        }
    }

    private func spawn(_ name: String, qos: QualityOfService, _ body: @escaping () -> Void) {
        group.enter()
        let thread = Thread { [self] in
            body()
            group.leave()
        }
        thread.name = name
        thread.qualityOfService = qos
        thread.start()
    }

    /// Pseudo stream index for audio demuxed by TSAudioTap instead of FFmpeg.
    public static let tappedAudioIndex: Int32 = -2

    /// Timeshift: playback "at the live edge" stays this far behind the newest data, so
    /// channels that deliver in bursts do not run dry between them.
    public static let liveLead: Double = {
        #if DEBUG
        // IPTV_LIVELEAD=<s>: start live closer to the newest data (tests the dry-player reconnect).
        if let lead = ProcessInfo.processInfo.environment["IPTV_LIVELEAD"].flatMap(Double.init) { return lead }
        #endif
        return 5
    }()

    /// TS PIDs (per stream URL path) whose audio has to be pulled out by TSAudioTap.
    /// Remembered so the next open of such a channel skips the failed probe.
    static let rescueStore = "player.audioRescuePIDs"
    static let rescueLock = NSLock()
    var audioTap: TSAudioTap?

    var rescueKey: String { url.path }

    private func openInput() throws {
        #if DEBUG
        try simulateNoData()
        #endif
        try source.open()

        // Xtream panels redirect offline live channels to a looping placeholder clip.
        if isLive, let final = source.finalURL?.absoluteString.lowercased(),
           final.contains("stream_offline") || final.contains("offline.mp4") {
            throw PlayerError.offline
        }

        let known = isLive ? knownRescuePIDs() : []
        if let pid = known.first { installAudioTap(pid: pid) }
        let ctx = try openFormat(ignoring: known)

        // Audio that probing cannot identify is usually an endless PES (see TSAudioTap):
        // reconnect once with the tap in place so it is demuxed from the first byte.
        let broken = Self.unresolvedAudio(ctx).subtracting(known)
        if isLive && known.isEmpty && audioTap == nil, let pid = broken.min(), !isStopped {
            AppLog.info(.player, "audio PID \(pid) without parameters, demuxing it via TSAudioTap")
            freeFormat()
            installAudioTap(pid: pid)
            try source.open()
            _ = try openFormat(ignoring: [pid])
        }
        if known.isEmpty, let pid = audioTap?.pid { rememberRescuePIDs([Int32(pid)]) }
    }

    /// Stream ids (PIDs) of audio streams that probing could not identify.
    private static func unresolvedAudio(_ ctx: UnsafeMutablePointer<AVFormatContext>) -> Set<Int32> {
        var result = Set<Int32>()
        for i in 0..<Int(ctx.pointee.nb_streams) {
            guard let st = ctx.pointee.streams[i] else { continue }
            let par = st.pointee.codecpar.pointee
            if par.codec_type == AVMEDIA_TYPE_AUDIO && (par.sample_rate == 0 || par.ch_layout.nb_channels == 0) {
                result.insert(st.pointee.id)
            }
        }
        return result
    }

    /// `ignoring`: PIDs handled by the tap; discarded so probing does not wait for them.
    private func openFormat(ignoring: Set<Int32>) throws -> UnsafeMutablePointer<AVFormatContext> {
        let opaque = Unmanaged.passUnretained(sourceBox).toOpaque()
        let seekable: Int32 = (!isLive && source.supportsRanges) ? 1 : 0
        guard let pb = ffs_avio_alloc(opaque, 256 * 1024, seekable, ioRead, ioSeek) else {
            throw PlayerError.message(String(localized: "Out of memory", bundle: .module))
        }
        self.pb = pb

        var ctx = avformat_alloc_context()
        guard let allocated = ctx else { throw PlayerError.message(String(localized: "Out of memory", bundle: .module)) }
        allocated.pointee.pb = pb
        allocated.pointee.flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_FLAG_GENPTS
        if liveTimeline { allocated.pointee.flags |= AVFMT_FLAG_DISCARD_CORRUPT }
        ffs_set_interrupt(allocated, ioInterrupt, opaque)

        var opts: OpaquePointer?
        if timeshift != nil {
            // Our own muxer wrote it: every stream is declared up front.
            av_dict_set(&opts, "probesize", "5000000", 0)
            av_dict_set(&opts, "analyzeduration", "2000000", 0)
        } else if isLive {
            // Upper bounds only: probing stops as soon as every stream has parameters.
            // UHD feeds run at ~50 Mbit/s, where a few MB hold no audio packet yet.
            av_dict_set(&opts, "probesize", "15000000", 0)
            // Tapped PIDs never resolve, so FFmpeg would wait out the whole window for them.
            av_dict_set(&opts, "analyzeduration", ignoring.isEmpty ? "5000000" : "1000000", 0)
        }
        // Only skip probing when the server says it is MPEG-TS; redirects can change the container.
        let isTS = source.mimeType == "video/mp2t" || source.mimeType == "video/mpeg"
        let hint: UnsafePointer<AVInputFormat>? = isTS ? av_find_input_format("mpegts") : nil
        let ret = avformat_open_input(&ctx, url.absoluteString, hint, &opts)
        av_dict_free(&opts)
        guard ret >= 0, let ctx else {
            throw PlayerError.message(isStopped ? String(localized: "Canceled", bundle: .module) : String(localized: "Could not open the stream (\(Int(ret)))", bundle: .module))
        }
        fmt = ctx

        if !ignoring.isEmpty {
            for i in 0..<Int(ctx.pointee.nb_streams) {
                guard let st = ctx.pointee.streams[i], ignoring.contains(st.pointee.id) else { continue }
                st.pointee.discard = AVDISCARD_ALL
            }
        }

        if avformat_find_stream_info(ctx, nil) < 0 && !isStopped {
            throw PlayerError.message(String(localized: "No playable tracks found", bundle: .module))
        }
        if isStopped { throw PlayerError.message(String(localized: "Canceled", bundle: .module)) }
        return ctx
    }

    private func selectStreams() throws {
        guard let ctx = fmt else { throw PlayerError.message(String(localized: "No playable tracks found", bundle: .module)) }

        // Stream selection: best video, audio in the user's language if available.
        var v = av_find_best_stream(ctx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        if v >= 0, ffs_is_attached_pic(ctx.pointee.streams[Int(v)]) != 0 { v = -1 }
        var a = av_find_best_stream(ctx, AVMEDIA_TYPE_AUDIO, -1, v, nil, 0)

        var audioTracks: [MediaTrack] = []
        var subtitleTracks: [MediaTrack] = []
        for i in 0..<Int32(ctx.pointee.nb_streams) {
            guard let st = ctx.pointee.streams[Int(i)] else { continue }
            let par = st.pointee.codecpar.pointee
            let lang = ffs_metadata(st.pointee.metadata, "language").map { String(cString: $0) }
            let title = ffs_metadata(st.pointee.metadata, "title").map { String(cString: $0) }
            if par.codec_type == AVMEDIA_TYPE_AUDIO {
                // Unidentified audio (no sample rate) cannot be decoded; leave it out.
                guard par.sample_rate > 0 else { continue }
                var parts = [MediaNames.language(lang) ?? String(localized: "Track \(audioTracks.count + 1)", bundle: .module)]
                if let title, !title.isEmpty, title != lang { parts.append(title) }
                parts.append(MediaNames.audioCodec(par.codec_id))
                parts.append(MediaNames.channels(par.ch_layout.nb_channels))
                audioTracks.append(MediaTrack(id: i, title: parts.joined(separator: " · "), language: MediaNames.languageCode(lang),
                                              isDefault: st.pointee.disposition & AV_DISPOSITION_DEFAULT != 0))
            } else if par.codec_type == AVMEDIA_TYPE_SUBTITLE && (ffs_is_text_subtitle(par.codec_id) != 0 || Self.isBitmapSubtitle(par.codec_id)) {
                var parts = [MediaNames.language(lang) ?? String(localized: "Subtitles \(subtitleTracks.count + 1)", bundle: .module)]
                if let title, !title.isEmpty, title != lang { parts.append(title) }
                subtitleTracks.append(MediaTrack(id: i, title: parts.joined(separator: " · "), language: MediaNames.languageCode(lang),
                                                 isForced: st.pointee.disposition & AV_DISPOSITION_FORCED != 0 || MediaNames.titleSaysForced(title),
                                                 isDefault: st.pointee.disposition & AV_DISPOSITION_DEFAULT != 0))
            }
        }
        let choice: (audio: Int32?, subtitle: Int32?)
        switch trackRequest {
        case .preferences(let preferences): choice = TrackChooser.choose(audio: audioTracks, subtitles: subtitleTracks, preferences: preferences)
        case .explicit(let audio, let subtitle): choice = (audio, subtitle)
        }
        if let chosen = choice.audio, audioTracks.contains(where: { $0.id == chosen }) { a = chosen }
        if a < 0, let first = audioTracks.first { a = first.id }
        let chosenSubtitle = choice.subtitle.flatMap { id in subtitleTracks.contains { $0.id == id } ? id : nil }
        if let chosenSubtitle, let st = ctx.pointee.streams[Int(chosenSubtitle)] {
            subCtx = ffs_open_decoder(st, 0)
        }
        if isTuner {
            var kept = Set<Int32>()
            if v >= 0 { kept.insert(v) }
            if audioTap == nil { kept.formUnion(audioTracks.map(\.id)) }
            for i in 0..<Int32(ctx.pointee.nb_streams) {
                guard let st = ctx.pointee.streams[Int(i)] else { continue }
                let codec = st.pointee.codecpar.pointee.codec_id
                if codec == AV_CODEC_ID_DVB_SUBTITLE || codec == AV_CODEC_ID_DVB_TELETEXT { kept.insert(i) }
            }
            keptStreams = kept
        }
        if a < 0, audioTap != nil {
            a = Self.tappedAudioIndex
            audioTracks.append(MediaTrack(id: a, title: String(localized: "Audio · AAC (repaired from TS stream)", bundle: .module)))
        }

        lock.lock()
        videoIndex = v
        audioIndex = a
        subtitleIndex = subCtx != nil ? (chosenSubtitle ?? -1) : -1
        hasVideo = v >= 0
        hasAudio = a >= 0 || a == Self.tappedAudioIndex
        if timeshift != nil {
            // Buffer time = stream time minus the muxer's fixed delay.
            timeOffset = ffs_mux_delay()
        } else if ctx.pointee.start_time != ffs_nopts() {
            timeOffset = Double(ctx.pointee.start_time) / Double(ffs_time_base())
        }
        lock.unlock()
        updateDiscardFlags()

        if let tunerOutput {
            let clock = v >= 0 ? v : (a == Self.tappedAudioIndex ? Self.tappedAudioIndex : a)
            let usable = tunerOutput.streamsOpened(ctx, kept: keptStreams.sorted(), clock: clock, tappedAudio: audioTap != nil && a == Self.tappedAudioIndex)
            guard usable else { throw PlayerError.unsupported }
        }

        guard v >= 0 || a >= 0 || a == Self.tappedAudioIndex else { throw PlayerError.message(String(localized: "No playable tracks found", bundle: .module)) }

        var duration: Double?
        if !liveTimeline && ctx.pointee.duration != ffs_nopts() && ctx.pointee.duration > 0 {
            duration = Double(ctx.pointee.duration) / Double(ffs_time_base())
        }

        // Static stats
        lock.lock()
        stats.container = String(cString: ctx.pointee.iformat.pointee.name).components(separatedBy: ",").first ?? ""
        var unsupportedDolbyVision: String?
        if v >= 0, let st = ctx.pointee.streams[Int(v)] {
            let par = st.pointee.codecpar.pointee
            stats.videoCodec = MediaNames.videoCodec(par.codec_id)
            stats.dynamicRange = Self.dynamicRange(par)
            if let dv = DVDecoder.Config(st.pointee.codecpar) {
                if DVDecoder.supports(st.pointee.codecpar, config: dv) {
                    stats.dynamicRange = "Dolby Vision \(dv.name)"
                } else if dv.profile == 5 {
                    // No base layer to fall back to: the colours would be wrong.
                    unsupportedDolbyVision = dv.name
                } else {
                    stats.dynamicRange = "Dolby Vision \(dv.name) → \(Self.dynamicRange(par, ignoringDolbyVision: true))"
                }
            }
        }
        if a == Self.tappedAudioIndex {
            stats.audio = String(localized: "AAC (TS repair)", bundle: .module)
        }
        if a >= 0, let st = ctx.pointee.streams[Int(a)] {
            let par = st.pointee.codecpar.pointee
            stats.audio = "\(MediaNames.audioCodec(par.codec_id)) \(MediaNames.channels(par.ch_layout.nb_channels)) · \(par.sample_rate / 1000) kHz"
        }
        lock.unlock()
        if let unsupportedDolbyVision {
            throw PlayerError.message(String(localized: "Dolby Vision \(unsupportedDolbyVision) is not supported on this Mac", bundle: .module))
        }

        let audioUsable = a >= 0 || a == Self.tappedAudioIndex
        emit(.opened(MediaInfo(duration: duration, isLive: liveTimeline, hasVideo: v >= 0, hasAudio: audioUsable,
                               audioTracks: audioTracks, subtitleTracks: subtitleTracks,
                               selectedAudio: audioUsable ? a : nil, selectedSubtitle: subCtx != nil ? chosenSubtitle : nil)))
    }

    static func dynamicRange(_ par: AVCodecParameters, ignoringDolbyVision: Bool = false) -> String {
        if !ignoringDolbyVision, av_packet_side_data_get(par.coded_side_data, par.nb_coded_side_data, AV_PKT_DATA_DOVI_CONF) != nil {
            return "Dolby Vision"
        }
        switch par.color_trc {
        case AVCOL_TRC_SMPTE2084: return "HDR10 (PQ)"
        case AVCOL_TRC_ARIB_STD_B67: return "HLG"
        default: return "SDR"
        }
    }

    private func updateDiscardFlags() {
        guard let fmt else { return }
        lock.lock()
        let keep: Set<Int32> = isTuner ? keptStreams : [videoIndex, audioIndex, subtitleIndex]
        lock.unlock()
        for i in 0..<Int32(fmt.pointee.nb_streams) {
            fmt.pointee.streams[Int(i)]?.pointee.discard = keep.contains(i) ? AVDISCARD_DEFAULT : AVDISCARD_ALL
        }
    }

    private func route(_ pkt: UnsafeMutablePointer<AVPacket>, fmt: UnsafeMutablePointer<AVFormatContext>) {
        let index = pkt.pointee.stream_index
        guard let st = fmt.pointee.streams[Int(index)] else {
            av_packet_unref(pkt)
            return
        }
        let tb = av_q2d(st.pointee.time_base)
        let raw = pkt.pointee.pts != ffs_nopts() ? pkt.pointee.pts : pkt.pointee.dts
        let sec: Double? = raw != ffs_nopts() ? Double(raw) * tb : nil

        lock.lock()
        let v = videoIndex, a = audioIndex, s = subtitleIndex
        lock.unlock()

        if let tunerOutput {
            if keptStreams.contains(index), admitLive(pkt, index: index, isVideo: index == v, tb: tb) {
                let cut = connections[packetConnection[index] ?? 0].cut
                if cut != 0 {
                    let delta = Int64((cut / tb).rounded())
                    if pkt.pointee.pts != ffs_nopts() { pkt.pointee.pts -= delta }
                    if pkt.pointee.dts != ffs_nopts() { pkt.pointee.dts -= delta }
                }
                tunerOutput.packet(pkt, input: index, timeBase: st.pointee.time_base)
            }
            av_packet_unref(pkt)
            return
        }

        if index == v || index == a {
            if isLive && !admitLive(pkt, index: index, isVideo: index == v, tb: tb) {
                av_packet_unref(pkt)
                return
            }
            if isLive {
                let cut = connections[packetConnection[index] ?? 0].cut
                if cut != 0 {
                    let delta = Int64((cut / tb).rounded())
                    if pkt.pointee.pts != ffs_nopts() { pkt.pointee.pts -= delta }
                    if pkt.pointee.dts != ffs_nopts() { pkt.pointee.dts -= delta }
                }
            }
            // Re-read: admitLive may have moved the timestamps (debug clock skew), and the cut did.
            let ts = pkt.pointee.pts != ffs_nopts() ? pkt.pointee.pts : pkt.pointee.dts
            let sec: Double? = ts != ffs_nopts() ? Double(ts) * tb : nil
            if isLive, let sec, detectDiscontinuity(index: index, sec: sec, isVideo: index == v) {
                resync()
            }
            guard let copy = av_packet_alloc() else {
                av_packet_unref(pkt)
                return
            }
            av_packet_move_ref(copy, pkt)
            lock.lock()
            let itemSerial = serial
            if let sec {
                if index == v { videoDemuxedUntil = max(videoDemuxedUntil, sec) }
                else { audioDemuxedUntil = max(audioDemuxedUntil, sec) }
            }
            lock.unlock()
            (index == v ? videoQ : audioQ).put(.packet(copy, serial: itemSerial))
        } else if index == s, let subCtx, Self.isBitmapSubtitle(subCtx.pointee.codec_id) {
            decodeBitmapSubtitle(pkt, ctx: subCtx, sec: sec, tb: tb)
            av_packet_unref(pkt)
        } else if index == s, let subCtx {
            var text: UnsafeMutablePointer<CChar>?
            var start = 0.0, end = 0.0
            if ffs_decode_text_subtitle(subCtx, pkt, &text, &start, &end) == 1, let text {
                let string = String(cString: text)
                free(text)
                let base = (sec ?? 0) - timeOffset
                let duration = end >= 0 ? end : (pkt.pointee.duration > 0 ? Double(pkt.pointee.duration) * tb : 4)
                emit(.subtitle(SubtitleCue(start: base + start, end: base + duration, text: string)))
            }
            av_packet_unref(pkt)
        } else {
            av_packet_unref(pkt)
        }
    }

    private var lastClockPacket: Double?

    /// Live TS feeds occasionally jump (channel splice, encoder restart).
    private func detectDiscontinuity(index: Int32, sec: Double, isVideo: Bool) -> Bool {
        lock.lock()
        let clockIsVideo = hasVideo
        lock.unlock()
        guard isVideo == clockIsVideo else { return false }
        defer { lastClockPacket = sec }
        guard let last = lastClockPacket else { return false }
        if abs(sec - last) > 10 { AppLog.detail(.player, "discontinuity \(String(format: "%.2f", last)) → \(String(format: "%.2f", sec)), resync") }
        return abs(sec - last) > 10
    }

    private func resync() {
        lock.lock()
        serial += 1
        let s = serial
        prerolling = true
        prerollTarget = nil
        prerollStartedAt = Date()
        startTime = nil
        firstAudioPTS = nil
        audioStartsLater = false
        buffering = false
        videoEnqueuedUntil = -.infinity
        audioEnqueuedUntil = -.infinity
        videoDemuxedUntil = -.infinity
        audioDemuxedUntil = -.infinity
        lock.unlock()
        sync.rate = 0
        videoQ.clear()
        audioQ.clear()
        videoQ.put(.flush(serial: s))
        audioQ.put(.flush(serial: s))
    }

    private func performSeek(to target: Double) {
        guard let fmt else { return }
        lock.lock()
        serial += 1
        let s = serial
        prerolling = true
        prerollTarget = target
        prerollStartedAt = Date()
        startTime = nil
        firstAudioPTS = nil
        audioStartsLater = false
        buffering = false
        eof = false
        endedSent = false
        videoDrained = false
        audioDrained = false
        videoEnqueuedUntil = -.infinity
        audioEnqueuedUntil = -.infinity
        videoDemuxedUntil = -.infinity
        audioDemuxedUntil = -.infinity
        lock.unlock()

        videoQ.clear()
        audioQ.clear()
        sync.setRate(0, time: CMTime(sec: target))

        if let timeshift, let buffered = source as? BufferByteSource {
            // Our index knows where every keyframe is; seek by byte.
            // (av_seek_frame's byte mode clamps to a file size, which a growing buffer has none of.)
            if let entry = timeshift.entry(atOrBefore: target - timeOffset) {
                avformat_flush(fmt)
                avio_seek(fmt.pointee.pb, buffered.position(ofBufferOffset: entry.offset), SEEK_SET)
            }
        } else {
            let ts = Int64(target * Double(ffs_time_base()))
            if avformat_seek_file(fmt, -1, Int64.min, ts, ts, 0) < 0 {
                av_seek_frame(fmt, -1, ts, AVSEEK_FLAG_BACKWARD)
            }
        }
        if let subCtx { avcodec_flush_buffers(subCtx) }
        emit(.clearSubtitles)
        videoQ.put(.flush(serial: s))
        audioQ.put(.flush(serial: s))
    }

    private func markEOF() {
        lock.lock()
        eof = true
        let s = serial
        lock.unlock()
        videoQ.put(.eof(serial: s))
        audioQ.put(.eof(serial: s))
    }

    private func applyTrackChanges(audio: Int32?, subtitle: Int32??) {
        guard let fmt else { return }
        if let audio {
            lock.lock()
            audioIndex = audio
            lock.unlock()
        }
        if let subtitle {
            if let subCtx {
                var ctx: UnsafeMutablePointer<AVCodecContext>? = subCtx
                avcodec_free_context(&ctx)
                self.subCtx = nil
            }
            lock.lock()
            subtitleIndex = subtitle ?? -1
            lock.unlock()
            if let index = subtitle, let st = fmt.pointee.streams[Int(index)] {
                subCtx = ffs_open_decoder(st, 0)
            }
        }
        updateDiscardFlags()
        // Already-demuxed packets belong to the old selection: re-read from here.
        if isLive {
            resync()
        } else {
            let now = sync.currentTime().seconds
            performSeek(to: now.isFinite ? max(now, timeOffset) : timeOffset)
        }
    }

    // MARK: - Teardown

    private func freeFormat() {
        if let subCtx {
            var c: UnsafeMutablePointer<AVCodecContext>? = subCtx
            avcodec_free_context(&c)
            self.subCtx = nil
        }
        if fmt != nil {
            avformat_close_input(&fmt)
        }
        if pb != nil {
            ffs_avio_free(&pb)
        }
    }
}
