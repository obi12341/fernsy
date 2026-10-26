import AVFoundation
import CoreMedia
import CoreVideo

// FFmpeg custom-I/O trampolines (must be plain C function pointers; FrameGrabber uses them too).
/// Gives the C callbacks a concrete class to point at.
final class SourceBox {
    let source: ByteSource
    init(_ source: ByteSource) { self.source = source }
}

func ioRead(_ opaque: UnsafeMutableRawPointer?, _ buf: UnsafeMutablePointer<UInt8>?, _ size: Int32) -> Int32 {
    guard let opaque, let buf else { return Int32(ffs_error_eio()) }
    return Unmanaged<SourceBox>.fromOpaque(opaque).takeUnretainedValue().source.read(into: buf, size: Int(size))
}

func ioSeek(_ opaque: UnsafeMutableRawPointer?, _ offset: Int64, _ whence: Int32) -> Int64 {
    guard let opaque else { return -1 }
    return Unmanaged<SourceBox>.fromOpaque(opaque).takeUnretainedValue().source.seek(offset: offset, whence: whence)
}

func ioInterrupt(_ opaque: UnsafeMutableRawPointer?) -> Int32 {
    guard let opaque else { return 0 }
    return Unmanaged<SourceBox>.fromOpaque(opaque).takeUnretainedValue().source.isCancelled ? 1 : 0
}

private extension CMTime {
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
final class PlaybackSession {
    enum Mode {
        /// Straight from HTTP: VOD, or live without timeshift.
        case network(isLive: Bool)
        /// Live ingest without decoding; packets go to the output.
        case tuner(TunerOutput)
        /// A tuned channel's timeshift buffer. Start position -1 = live edge.
        case buffer(TimeshiftBuffer)
        /// A recording on disk.
        case file(FileByteSource)
    }

    enum Event {
        case opened(MediaInfo)
        case videoSize(CGSize)
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
        /// The audio renderer suggests a refill (output device changed, renderer failed).
        case audioNeedsRefill
        case ended
        /// `retry`: a live reconnect may help (network drop), as opposed to e.g. an offline channel.
        case failed(String, retry: Bool)
    }

    private let url: URL
    private let mode: Mode
    /// Network live stream (reconnect junctions, duplicate removal, audio rescue).
    private let isLive: Bool
    /// Plays a live timeline (live buffering rules), from the network or the buffer.
    private let liveTimeline: Bool
    private let tunerOutput: TunerOutput?
    private let timeshift: TimeshiftBuffer?
    /// Tuner: streams handed to the output (video, every audio track, DVB subtitles).
    private var keptStreams: Set<Int32> = []
    private let startPosition: Double
    /// The renderers' receivers; nil for the headless tuner, which never outputs anything.
    private let videoSink: VideoSink?
    private let audioSink: AudioSink?
    private let sync: AVSampleBufferRenderSynchronizer
    private let onEvent: (Event) -> Void

    private let source: ByteSource
    private let sourceBox: SourceBox
    private var fmt: UnsafeMutablePointer<AVFormatContext>?
    private var pb: UnsafeMutablePointer<AVIOContext>?
    private var subCtx: UnsafeMutablePointer<AVCodecContext>?
    private let trackRequest: TrackRequest

    private let videoQ = PacketQueue()
    private let audioQ = PacketQueue()
    private let group = DispatchGroup()
    private var monitor: DispatchSourceTimer?

    // MARK: Shared state (guarded by `lock`)

    private let lock = NSLock()
    private var stopped = false
    private var serial = 0
    private var videoIndex: Int32 = -1
    private var audioIndex: Int32 = -1
    private var subtitleIndex: Int32 = -1
    private var hasVideo = false
    private var hasAudio = false
    private var timeOffset = 0.0

    private var prerolling = true
    private var prerollTarget: Double?
    private var prerollStartedAt = Date()
    private var startTime: Double?
    private var firstAudioPTS: Double?
    /// The first audio sample of this preroll lies after the video start (late-starting audio).
    private var audioStartsLater = false
    private var userPaused = false
    private var buffering = false
    private var eof = false
    private var endedSent = false
    private var videoDrained = false
    private var audioDrained = false
    private var videoEnqueuedUntil = -Double.infinity
    private var audioEnqueuedUntil = -Double.infinity
    private var videoDemuxedUntil = -Double.infinity
    private var audioDemuxedUntil = -Double.infinity

    private var pendingSeek: Double?
    private var pendingAudio: Int32?
    private var pendingSubtitle: Int32??

    // Stats (guarded by `lock`)
    private var stats = PlaybackStats()
    private var framesPresented = 0
    private var lateDrops = 0
    /// Frames the video renderer could not decode (counted from enqueue results).
    private var decodeFailures = 0
    /// One recovery or refill request per flush (the output threads only).
    private var videoRecoveryRequested = false
    private var audioRefillRequested = false
    private var lastStatsAt = Date()
    private var lastStatsFrames = 0
    private var lastStatsBytes: Int64 = 0
    private var lastDisplaySize = CGSize.zero
    private let createdAt = Date()
    private var rebuffers = 0
    private var duplicatesDropped = 0

    // Live reconnect junctions (demux thread only). Every new connection starts with a replay
    // of the server's buffer, possibly from another backend with an unrelated clock. Packets
    // are compared on the output timeline (stream time minus the connection's cut): what was already
    // played is dropped, so playback continues seamlessly instead of jumping back.
    private var lastOut: [Int32: Double] = [:]
    private var history = ContentHistory(capacity: 8192)

    private struct Connection {
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
    private var connections = [Connection(start: 0, cut: 0, decided: true)]
    /// Per stream: connection of the latest packet carrying a byte position (packets split
    /// out of one PES report none and inherit it).
    private var packetConnection: [Int32: Int] = [:]
    /// Per stream: the newest connection in which it has moved past the replayed part.
    private var rejoinedConnection: [Int32: Int] = [:]
    private var needKeyframe = false
    // TSAudioTap frames on the output timeline. The tap sees bytes as they are read, ahead of
    // the demuxer, so its frames always belong to the newest connection.
    private var tapConnection = 0
    private var tapRejoining = false
    private var tapNextOut: Double?
    private var lastTapOut: Double?
    #if DEBUG
    private let debugClockSkew = ProcessInfo.processInfo.environment["IPTV_TESTCLOCK"].flatMap(Double.init) ?? 0
    #endif

    /// Runs on the video thread right before the first video frame goes to the renderer (the
    /// engine stops anything else feeding the renderer there, e.g. the PiP loading picture).
    var beforeFirstVideo: (() -> Void)?
    /// Receives every video frame that goes to the renderer.
    var lastPicture: LastPicture?
    private var sentVideo = false

    init(url: URL, mode: Mode, startPosition: Double, tracks: TrackRequest = .preferences(TrackPreferences()),
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
    convenience init(tunerURL: URL, output: TunerOutput, onEvent: @escaping (Event) -> Void) {
        self.init(url: tunerURL, mode: .tuner(output), startPosition: 0,
                  videoSink: nil, audioSink: nil,
                  synchronizer: AVSampleBufferRenderSynchronizer(), onEvent: onEvent)
    }

    private var isTuner: Bool { tunerOutput != nil }

    /// Network counters of the source (for a tuner: its connection).
    var networkStats: (HTTPByteSource.NetStats, Int64) {
        (source.netStats, source.totalBytesReceived)
    }

    /// Tuner: the connection's health and a recovery via another server (watchdog queue).
    func observeConnection(health: @escaping (HTTPByteSource.Health) -> Void, recovered: @escaping () -> Void) {
        guard let http = source as? HTTPByteSource else { return }
        http.onHealth = health
        http.onRecovered = recovered
    }

    /// Tuner: how much the slowest consumer still has ahead (stall detection).
    func reportPlaybackAhead(_ seconds: Double) {
        source.reportPlaybackAhead(seconds)
    }

    deinit {
        freeFormat()
    }

    // MARK: Public control (thread-safe)

    func start() {
        group.enter()
        let thread = Thread { [self] in demuxMain() }
        thread.name = "player.demux"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Blocks until every thread has exited. Never call from a session thread.
    func stop() {
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

    func setPaused(_ paused: Bool) {
        lock.lock()
        defer { lock.unlock() }
        userPaused = paused
        guard !prerolling else { return }
        sync.rate = (paused || buffering) ? 0 : 1
    }

    /// `position` is in display time (0 = start of media).
    func seek(to position: Double) {
        guard !isLive else { return }
        lock.lock()
        pendingSeek = max(0, position) + timeOffset
        lock.unlock()
    }

    func selectAudio(_ index: Int32) {
        lock.lock()
        pendingAudio = index
        lock.unlock()
    }

    func selectSubtitle(_ index: Int32?) {
        lock.lock()
        pendingSubtitle = .some(index)
        lock.unlock()
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func emit(_ event: Event) {
        let handler = onEvent
        DispatchQueue.main.async { handler(event) }
    }

    // MARK: - Demuxer

    private func demuxMain() {
        defer { group.leave() }
        if let timeshift, !timeshift.waitForContent(seconds: 0, timeout: 25, cancelled: { isStopped }) {
            if !isStopped { emit(.failed(String(localized: "Keine Daten vom Sender"), retry: true)) }
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
                    if !isStopped { emit(.failed(String(localized: "Stream unterbrochen"), retry: true)) }
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
                    emit(.failed(String(localized: "Stream unterbrochen"), retry: true))
                    break
                }
                if ret != ffs_error_eof() && fmt.pointee.pb?.pointee.eof_reached == 0 {
                    // Network error mid-file: surface it rather than pretending we ended.
                    emit(.failed(String(localized: "Verbindung verloren"), retry: false))
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
    static let tappedAudioIndex: Int32 = -2

    /// Timeshift: playback "at the live edge" stays this far behind the newest data, so
    /// channels that deliver in bursts do not run dry between them.
    static let liveLead: Double = {
        #if DEBUG
        // IPTV_LIVELEAD=<s>: start live closer to the newest data (tests the dry-player reconnect).
        if let lead = ProcessInfo.processInfo.environment["IPTV_LIVELEAD"].flatMap(Double.init) { return lead }
        #endif
        return 5
    }()

    /// TS PIDs (per stream URL path) whose audio has to be pulled out by TSAudioTap.
    /// Remembered so the next open of such a channel skips the failed probe.
    private static let rescueStore = "player.audioRescuePIDs"
    private static let rescueLock = NSLock()
    private var audioTap: TSAudioTap?

    private var rescueKey: String { url.path }

    private func knownRescuePIDs() -> Set<Int32> {
        Self.rescueLock.lock(); defer { Self.rescueLock.unlock() }
        let all = UserDefaults.standard.dictionary(forKey: Self.rescueStore) as? [String: [Int]] ?? [:]
        return Set((all[rescueKey] ?? []).map(Int32.init))
    }

    private func rememberRescuePIDs(_ pids: Set<Int32>) {
        Self.rescueLock.lock(); defer { Self.rescueLock.unlock() }
        var all = UserDefaults.standard.dictionary(forKey: Self.rescueStore) as? [String: [Int]] ?? [:]
        all[rescueKey] = pids.isEmpty ? nil : pids.map(Int.init)
        UserDefaults.standard.set(all, forKey: Self.rescueStore)
    }

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

    private func installAudioTap(pid: Int32) {
        let tap = TSAudioTap(pid: Int(pid))
        tap.onFrame = { [weak self] frame in self?.enqueueTapped(frame) }
        audioTap = tap
        source.tap = { [weak tap] bytes in tap?.feed(bytes) }
    }

    /// Demux thread, inside `read`: the next bytes come from a reconnected live stream.
    private func rejoin(at offset: Int64) {
        audioTap?.reset()
        connections.append(Connection(start: offset, cut: connections[connections.count - 1].cut, decided: false))
        tapConnection = connections.count - 1
        tapRejoining = audioTap != nil
        AppLog.detail(.player, "rejoining live stream after reconnect at byte \(offset)")
    }

    private func countDuplicate() {
        lock.lock()
        duplicatesDropped += 1
        lock.unlock()
    }

    /// Live: drops packets a reconnected stream repeats, lines each new connection's clock up
    /// with what was played, and after a real gap holds video back until a keyframe so the
    /// decoder does not show broken references.
    private func admitLive(_ pkt: UnsafeMutablePointer<AVPacket>, index: Int32, isVideo: Bool, tb: Double) -> Bool {
        guard pkt.pointee.dts != ffs_nopts() || pkt.pointee.pts != ffs_nopts() else { return !(isVideo && needKeyframe) }
        let connection = connectionIndex(of: pkt, index: index)
        #if DEBUG
        // IPTV_TESTCLOCK=<seconds>: every reconnect lands on a "backend" whose clock is that
        // much further ahead, like the provider's load balancer does.
        if debugClockSkew != 0 && connection > 0 {
            let skew = Int64(debugClockSkew * Double(connection) / tb)
            if pkt.pointee.pts != ffs_nopts() { pkt.pointee.pts += skew }
            if pkt.pointee.dts != ffs_nopts() { pkt.pointee.dts += skew }
        }
        #endif
        let raw = pkt.pointee.dts != ffs_nopts() ? pkt.pointee.dts : pkt.pointee.pts
        let streamTime = Double(raw) * tb
        // Content keys only for the stream that drives alignment (video, or audio for radio):
        // audio has too many identical frames (silence) to place reliably.
        let aligns = isVideo || !hasVideoStream
        let key = aligns && pkt.pointee.data != nil
            ? ContentHistory.key(UnsafeRawBufferPointer(start: pkt.pointee.data, count: Int(pkt.pointee.size)), salt: Int(index))
            : nil

        if connection > rejoinedConnection[index] ?? 0 {
            if let last = lastOut[index] {
                if !connections[connection].decided, let key, let known = history.time(of: key) {
                    connections[connection].cut = streamTime - known
                    connections[connection].decided = true
                    AppLog.detail(.player, "connection \(connection) lined up by content, clock offset \(String(format: "%.2f", connections[connection].cut - connections[connection - 1].cut)) s")
                    countDuplicate()
                    return false
                }
                let out = streamTime - connections[connection].cut
                if out <= last + 0.001 && last - out < 60 {
                    countDuplicate()
                    return false
                }
                let gap = out - last
                // A big jump may be another backend's clock: wait a little for a content match
                // before treating it as a real discontinuity.
                if !connections[connection].decided && (gap > 10 || gap < -60) && connections[connection].alignWait < 150 {
                    connections[connection].alignWait += 1
                    return false
                }
                AppLog.detail(.player, "rejoined \(isVideo ? "video" : "audio") stream in connection \(connection), gap \(String(format: "%.2f", gap)) s, \(duplicatesDropped) duplicates dropped so far")
                if isVideo && gap > 0.5 { needKeyframe = true }
                // The first stream to rejoin decides the cut for both, keeping them in sync.
                // Larger jumps are discontinuities and handled by a resync instead.
                if !connections[connection].decided {
                    connections[connection].decided = true
                    if gap > 0.5 && gap < 10 { connections[connection].cut += gap - 0.04 }
                }
            }
            rejoinedConnection[index] = connection
        }
        if isVideo && needKeyframe {
            guard pkt.pointee.flags & AV_PKT_FLAG_KEY != 0 else { return false }
            needKeyframe = false
        }
        let out = streamTime - connections[connection].cut
        lastOut[index] = out
        if let key { history.insert(key, time: out) }
        return true
    }

    private func connectionIndex(of pkt: UnsafeMutablePointer<AVPacket>, index: Int32) -> Int {
        let pos = pkt.pointee.pos
        if pos >= 0 {
            packetConnection[index] = connections.lastIndex { $0.start <= pos } ?? 0
        }
        return packetConnection[index] ?? 0
    }

    private var hasVideoStream: Bool {
        lock.lock(); defer { lock.unlock() }
        return hasVideo
    }

    /// Runs on the demux thread (inside FFmpeg's read callback).
    private func enqueueTapped(_ frame: TSAudioTap.Frame) {
        let duration = Double(frame.duration) / 90_000
        let key = frame.data.withUnsafeBytes { ContentHistory.key($0, salt: -2) }
        if tapRejoining {
            if history.time(of: key) != nil {
                // Replayed: skip it.
                countDuplicate()
                return
            }
            // Until the video has lined the new connection up, its timestamps mean nothing.
            // (Radio-only taps have no video to wait for and simply continue.)
            if !connections[tapConnection].decided && hasVideoStream { return }
            tapRejoining = false
        }
        // Without a timestamp (after a reconnect, until the next PES header) the audio simply
        // continues where it left off.
        let out = frame.pts.map { Double($0) / 90_000 - connections[tapConnection].cut } ?? tapNextOut
        guard let out else { return }
        if let last = lastTapOut, out < last + duration / 2, last - out < 60 {
            countDuplicate()
            return
        }
        lastTapOut = out
        tapNextOut = out + duration
        history.insert(key, time: out)

        let pts = Int64((out * 90_000).rounded())
        let packet = frame.data.withUnsafeBytes { raw in
            ffs_packet_from_bytes(raw.bindMemory(to: UInt8.self).baseAddress, Int32(frame.data.count), pts, frame.duration)
        }
        guard let packet else { return }
        if let tunerOutput {
            tunerOutput.packet(packet, input: Self.tappedAudioIndex, timeBase: AVRational(num: 1, den: 90_000))
            var p: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&p)
            return
        }
        lock.lock()
        let itemSerial = serial
        audioDemuxedUntil = max(audioDemuxedUntil, out)
        lock.unlock()
        audioQ.put(.packet(packet, serial: itemSerial))
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
            throw PlayerError.message(String(localized: "Speicherfehler"))
        }
        self.pb = pb

        var ctx = avformat_alloc_context()
        guard let allocated = ctx else { throw PlayerError.message(String(localized: "Speicherfehler")) }
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
            throw PlayerError.message(isStopped ? String(localized: "Abgebrochen") : String(localized: "Stream konnte nicht geöffnet werden (\(Int(ret)))"))
        }
        fmt = ctx

        if !ignoring.isEmpty {
            for i in 0..<Int(ctx.pointee.nb_streams) {
                guard let st = ctx.pointee.streams[i], ignoring.contains(st.pointee.id) else { continue }
                st.pointee.discard = AVDISCARD_ALL
            }
        }

        if avformat_find_stream_info(ctx, nil) < 0 && !isStopped {
            throw PlayerError.message(String(localized: "Keine abspielbaren Spuren gefunden"))
        }
        if isStopped { throw PlayerError.message(String(localized: "Abgebrochen")) }
        return ctx
    }

    private func selectStreams() throws {
        guard let ctx = fmt else { throw PlayerError.message(String(localized: "Keine abspielbaren Spuren gefunden")) }

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
                var parts = [MediaNames.language(lang) ?? String(localized: "Spur \(audioTracks.count + 1)")]
                if let title, !title.isEmpty, title != lang { parts.append(title) }
                parts.append(MediaNames.audioCodec(par.codec_id))
                parts.append(MediaNames.channels(par.ch_layout.nb_channels))
                audioTracks.append(MediaTrack(id: i, title: parts.joined(separator: " · "), language: MediaNames.languageCode(lang),
                                              isDefault: st.pointee.disposition & AV_DISPOSITION_DEFAULT != 0))
            } else if par.codec_type == AVMEDIA_TYPE_SUBTITLE && (ffs_is_text_subtitle(par.codec_id) != 0 || Self.isBitmapSubtitle(par.codec_id)) {
                var parts = [MediaNames.language(lang) ?? String(localized: "Untertitel \(subtitleTracks.count + 1)")]
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
            audioTracks.append(MediaTrack(id: a, title: String(localized: "Audio · AAC (aus TS-Strom repariert)")))
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

        guard v >= 0 || a >= 0 || a == Self.tappedAudioIndex else { throw PlayerError.message(String(localized: "Keine abspielbaren Spuren gefunden")) }

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
            stats.audio = String(localized: "AAC (TS-Reparatur)")
        }
        if a >= 0, let st = ctx.pointee.streams[Int(a)] {
            let par = st.pointee.codecpar.pointee
            stats.audio = "\(MediaNames.audioCodec(par.codec_id)) \(MediaNames.channels(par.ch_layout.nb_channels)) · \(par.sample_rate / 1000) kHz"
        }
        lock.unlock()
        if let unsupportedDolbyVision {
            throw PlayerError.message(String(localized: "Dolby Vision \(unsupportedDolbyVision) wird auf diesem Mac nicht unterstützt"))
        }

        let audioUsable = a >= 0 || a == Self.tappedAudioIndex
        emit(.opened(MediaInfo(duration: duration, isLive: liveTimeline, hasVideo: v >= 0, hasAudio: audioUsable,
                               audioTracks: audioTracks, subtitleTracks: subtitleTracks,
                               selectedAudio: audioUsable ? a : nil, selectedSubtitle: subCtx != nil ? chosenSubtitle : nil)))
    }

    private static func dynamicRange(_ par: AVCodecParameters, ignoringDolbyVision: Bool = false) -> String {
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

    static func isBitmapSubtitle(_ codec: AVCodecID) -> Bool {
        codec == AV_CODEC_ID_HDMV_PGS_SUBTITLE || codec == AV_CODEC_ID_DVD_SUBTITLE || codec == AV_CODEC_ID_DVB_SUBTITLE
    }

    private func decodeBitmapSubtitle(_ pkt: UnsafeMutablePointer<AVPacket>, ctx: UnsafeMutablePointer<AVCodecContext>, sec: Double?, tb: Double) {
        var rects: UnsafeMutablePointer<FFSBitmapRect>?
        var start = 0.0, end = 0.0
        var width: Int32 = 0, height: Int32 = 0
        let count = ffs_decode_bitmap_subtitle(ctx, pkt, &rects, &start, &end, &width, &height)
        guard count >= 0 else { return }
        defer { ffs_free_bitmap_rects(rects, count) }
        var pieces: [BitmapCue.Piece] = []
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        for i in 0..<Int(count) {
            guard let r = rects?[i] else { continue }
            let length = Int(r.w) * Int(r.h) * 4
            guard let provider = CGDataProvider(data: Data(bytes: r.pixels, count: length) as CFData),
                  let image = CGImage(width: Int(r.w), height: Int(r.h), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(r.w) * 4,
                                      space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                                      intent: .defaultIntent) else { continue }
            pieces.append(BitmapCue.Piece(image: image, rect: CGRect(x: Int(r.x), y: Int(r.y), width: Int(r.w), height: Int(r.h))))
        }
        let base = (sec ?? 0) - timeOffset
        emit(.bitmapSubtitle(BitmapCue(start: base + start, end: end >= 0 ? base + end : .infinity, pieces: pieces,
                                       canvas: CGSize(width: Int(width), height: Int(height)))))
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

    // MARK: - Video

    private func videoMain() {
        lock.lock()
        let index = videoIndex
        lock.unlock()
        var dv: DVDecoder?
        if let fmt, let st = fmt.pointee.streams[Int(index)], let config = DVDecoder.Config(st.pointee.codecpar),
           DVDecoder.supports(st.pointee.codecpar, config: config) {
            dv = DVDecoder(stream: st, config: config)
            if dv == nil && config.profile == 5 {
                emit(.failed(String(localized: "Dolby Vision \(config.name) wird auf diesem Mac nicht unterstützt"), retry: false))
            }
        }
        var ctx: UnsafeMutablePointer<AVCodecContext>?
        if dv == nil, let fmt, let st = fmt.pointee.streams[Int(index)] { ctx = ffs_open_decoder(st, 1) }
        guard let fmt, let st = fmt.pointee.streams[Int(index)], dv != nil || ctx != nil else {
            lock.lock()
            hasVideo = false
            videoDrained = true
            lock.unlock()
            return
        }
        let streamTB = st.pointee.time_base
        let rate = st.pointee.avg_frame_rate.num > 0 ? st.pointee.avg_frame_rate : st.pointee.r_frame_rate
        let nominalDuration = rate.num > 0 ? Double(rate.den) / Double(rate.num) : 0.04

        guard let frame = av_frame_alloc(), let filtered = av_frame_alloc() else { return }
        var pixconv = ffs_pixconv_alloc()
        var deint: OpaquePointer?
        var deintFailed = false
        var formatDescription: CMVideoFormatDescription?
        var lastPTS: Double?
        var mySerial = 0

        defer {
            var f: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&f)
            var g: UnsafeMutablePointer<AVFrame>? = filtered
            av_frame_free(&g)
            ffs_deint_free(&deint)
            ffs_pixconv_free(&pixconv)
            avcodec_free_context(&ctx)
        }

        /// `filtered`: frames from the filter graph carry their timestamp in `pts` (rescaled to the
        /// sink time base); `best_effort_timestamp` is still in the decoder's time base there.
        func present(_ f: UnsafeMutablePointer<AVFrame>, tb: AVRational, filtered: Bool = false) {
            let q = av_q2d(tb)
            var pts = filtered ? f.pointee.pts : f.pointee.best_effort_timestamp
            if pts == ffs_nopts() { pts = f.pointee.pts }
            let duration = f.pointee.duration > 0 ? Double(f.pointee.duration) * q : nominalDuration / (deint != nil ? 2 : 1)
            let sec = pts != ffs_nopts() ? Double(pts) * q : (lastPTS.map { $0 + duration } ?? 0)
            lastPTS = sec

            guard let pixelBuffer = ffs_frame_to_pixbuf(pixconv, f) else { return }

            if formatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
                var fd: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &fd)
                formatDescription = fd
                updateVideoStats(pixelBuffer: pixelBuffer, sar: f.pointee.sample_aspect_ratio,
                                 decoder: f.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue ? "VideoToolbox (Hardware)" : "Software")
            }
            guard let formatDescription else { return }

            var timing = CMSampleTimingInfo(duration: CMTime(sec: duration), presentationTimeStamp: CMTime(sec: sec),
                                            decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: formatDescription,
                                                     sampleTiming: &timing, sampleBufferOut: &sample)
            guard let sample else { return }
            enqueueVideo(sample, sec: sec, duration: duration, serial: mySerial)
        }

        /// Dolby Vision frames: the decoder's own buffers, untouched (their DV attachments are what
        /// the display layer needs).
        func presentDolbyVision(_ frame: DVDecoder.Frame) {
            let pixelBuffer = frame.pixelBuffer
            let duration = nominalDuration
            if let lastPTS, frame.time <= lastPTS { AppLog.detail(.player, "DV frame out of order: \(frame.time) after \(lastPTS)") }
            lastPTS = frame.time
            if formatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
                var fd: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &fd)
                formatDescription = fd
                updateVideoStats(pixelBuffer: pixelBuffer, sar: st.pointee.codecpar.pointee.sample_aspect_ratio,
                                 decoder: String(localized: "VideoToolbox (Dolby Vision)"))
            }
            guard let formatDescription else { return }
            var timing = CMSampleTimingInfo(duration: CMTime(sec: duration), presentationTimeStamp: CMTime(sec: frame.time),
                                            decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: formatDescription,
                                                     sampleTiming: &timing, sampleBufferOut: &sample)
            guard let sample else { return }
            enqueueVideo(sample, sec: frame.time, duration: duration, serial: mySerial)
        }

        func handle(_ f: UnsafeMutablePointer<AVFrame>) {
            let interlaced = (f.pointee.flags & AV_FRAME_FLAG_INTERLACED) != 0
            if let d = deint, ffs_deint_matches(d, f) == 0 {
                ffs_deint_free(&deint)
            }
            if deint == nil && interlaced && !deintFailed {
                deint = ffs_deint_create(f, streamTB)
                if let d = deint {
                    lock.lock()
                    stats.deinterlace = ffs_deint_is_hw(d) != 0 ? "yadif (Metal, 2×)" : "bwdif (CPU, 2×)"
                    lock.unlock()
                } else {
                    deintFailed = true
                }
            }
            if let d = deint {
                guard ffs_deint_push(d, f) >= 0 else { return }
                let outTB = ffs_deint_time_base(d)
                while ffs_deint_pull(d, filtered) >= 0 {
                    present(filtered, tb: outTB, filtered: true)
                    av_frame_unref(filtered)
                }
            } else {
                present(f, tb: streamTB)
            }
        }

        func decode(_ pkt: UnsafeMutablePointer<AVPacket>?) {
            if let decoder = dv {
                guard let pkt else {
                    decoder.drain(output: presentDolbyVision)
                    return
                }
                let status = decoder.decode(pkt, output: presentDolbyVision)
                guard status != noErr, decoder.decodedFrames == 0 else { return }
                // Not a single frame: this Mac (or file) does not take the DV session after all.
                AppLog.error(.player, "Dolby Vision decode failed (\(status))")
                dv = nil
                if decoder.config.profile == 5 {
                    emit(.failed(String(localized: "Dolby Vision \(decoder.config.name) wird auf diesem Mac nicht unterstützt"), retry: false))
                    return
                }
                ctx = ffs_open_decoder(st, 1)
                lock.lock()
                stats.dynamicRange = "Dolby Vision \(decoder.config.name) → \(Self.dynamicRange(st.pointee.codecpar.pointee, ignoringDolbyVision: true))"
                lock.unlock()
                formatDescription = nil
            }
            guard let ctx else { return }
            var sent = avcodec_send_packet(ctx, pkt)
            while true {
                while avcodec_receive_frame(ctx, frame) >= 0 {
                    handle(frame)
                    av_frame_unref(frame)
                }
                guard sent == ffs_error_eagain() else { break }
                sent = avcodec_send_packet(ctx, pkt)
            }
        }

        while !isStopped {
            guard let item = videoQ.get() else { break }
            switch item {
            case .flush(let s):
                mySerial = s
                dv?.flush()
                if let ctx { avcodec_flush_buffers(ctx) }
                ffs_deint_free(&deint)
                lastPTS = nil
                videoSink?.flush()
                videoRecoveryRequested = false
            case .eof(let s):
                guard s == mySerial else { continue }
                decode(nil)
                if let d = deint {
                    ffs_deint_push(d, nil)
                    while ffs_deint_pull(d, filtered) >= 0 {
                        present(filtered, tb: ffs_deint_time_base(d), filtered: true)
                        av_frame_unref(filtered)
                    }
                    ffs_deint_free(&deint)
                }
                if let ctx { avcodec_flush_buffers(ctx) }
                lock.lock()
                videoDrained = true
                lock.unlock()
            case .packet(let pkt, let s):
                if s == mySerial { decode(pkt) }
                var p: UnsafeMutablePointer<AVPacket>? = pkt
                av_packet_free(&p)
            }
        }
    }

    private func updateVideoStats(pixelBuffer: CVPixelBuffer, sar: AVRational, decoder: String) {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let aspect = (sar.num > 0 && sar.den > 0) ? Double(sar.num) / Double(sar.den) : 1
        let display = CGSize(width: (Double(w) * aspect).rounded(), height: Double(h))

        let cvFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let formatName: String
        switch cvFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: formatName = String(localized: "NV12 (8 Bit)")
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: formatName = String(localized: "P010 (10 Bit)")
        // The Dolby Vision decoder hands out Apple's lossless-compressed layouts.
        case kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarFullRange: formatName = String(localized: "NV12 (8 Bit, komprimiert)")
        case kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange, kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange: formatName = String(localized: "P010 (10 Bit, komprimiert)")
        default: formatName = String(format: "%c%c%c%c", (cvFormat >> 24) & 0xff, (cvFormat >> 16) & 0xff, (cvFormat >> 8) & 0xff, cvFormat & 0xff)
        }

        lock.lock()
        stats.resolution = "\(w)×\(h)" + (aspect != 1 ? " → \(Int(display.width))×\(h)" : "")
        stats.pixelFormat = formatName
        stats.decoder = decoder
        let changed = display != lastDisplaySize
        lastDisplaySize = display
        lock.unlock()
        if changed { emit(.videoSize(display)) }
    }

    private func enqueueVideo(_ sample: CMSampleBuffer, sec: Double, duration: Double, serial s: Int) {
        while true {
            lock.lock()
            if stopped || s != serial {
                lock.unlock()
                return
            }
            if prerolling {
                if let target = prerollTarget, sec + duration <= target {
                    lock.unlock()
                    return
                }
                if startTime == nil { startTime = sec }
                let ahead = sec - startTime!
                lock.unlock()
                if ahead > 0.5 {
                    Thread.sleep(forTimeInterval: 0.005)
                    continue
                }
            } else {
                lock.unlock()
                let now = sync.currentTime().seconds
                if sec + duration < now - 0.2 {
                    lock.lock()
                    lateDrops += 1
                    lock.unlock()
                    return
                }
                if sec - now > 0.3 {
                    Thread.sleep(forTimeInterval: 0.008)
                    continue
                }
            }
            if !sentVideo {
                sentVideo = true
                beforeFirstVideo?()
            }
            // Taken before the hand-over: the receiver takes the sample.
            let image = lastPicture != nil ? CMSampleBufferGetImageBuffer(sample) : nil
            // Paced above (at most 0.3 s ahead), so the queue stays short without readiness checks.
            switch videoSink?.enqueue(sample) {
            case .needsFlush(let reason)?:
                // Once per flush: the engine resumes from the next key frame.
                if !videoRecoveryRequested {
                    videoRecoveryRequested = true
                    emit(.decoderNeedsFlush(reason))
                }
                return
            case .decodeFailures(let count)?:
                lock.lock()
                decodeFailures += count
                lock.unlock()
            default:
                break
            }
            if let lastPicture, let image { lastPicture.set(image) }
            lock.lock()
            videoEnqueuedUntil = max(videoEnqueuedUntil, sec + duration)
            framesPresented += 1
            lock.unlock()
            return
        }
    }

    // MARK: - Audio

    private func audioMain() {
        var ctx: UnsafeMutablePointer<AVCodecContext>?
        var openedIndex: Int32 = -1
        var resampler = ffs_resampler_alloc()
        var formatDescription: CMAudioFormatDescription?
        var fdKey = (rate: Int32(0), channels: Int32(0))
        var nextPTS: Double?
        var mySerial = 0
        #if DEBUG
        let meter = AudioLevelMeter()
        #endif
        guard let frame = av_frame_alloc() else { return }

        defer {
            var f: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&f)
            ffs_resampler_free(&resampler)
            avcodec_free_context(&ctx)
        }

        func ensureDecoder() {
            lock.lock()
            let wanted = audioIndex
            lock.unlock()
            guard wanted != openedIndex else { return }
            avcodec_free_context(&ctx)
            openedIndex = wanted
            if wanted == Self.tappedAudioIndex {
                ctx = ffs_open_decoder_id(AV_CODEC_ID_AAC, AVRational(num: 1, den: 90_000))
            } else if let fmt, wanted >= 0, let st = fmt.pointee.streams[Int(wanted)] {
                ctx = ffs_open_decoder(st, 0)
            }
        }

        // Decoded audio collected into blocks of at least ~20 ms: TrueHD frames hold 40 samples
        // (0.83 ms), and a renderer fed over a thousand such buffers per second stays silent.
        var block = Data()
        var blockStart = 0.0
        var blockFrames = 0
        var blockKey = (rate: Int32(0), channels: Int32(0))

        func sendBlock() {
            guard blockFrames > 0 else { return }
            defer {
                block.removeAll(keepingCapacity: true)
                blockFrames = 0
            }
            if formatDescription == nil || fdKey != blockKey {
                formatDescription = Self.makeAudioFormat(rate: blockKey.rate, channels: blockKey.channels)
                fdKey = blockKey
            }
            let frames = blockFrames, start = blockStart, rate = blockKey.rate, channels = blockKey.channels
            guard let formatDescription,
                  let sample = block.withUnsafeBytes({ raw in
                      Self.makeAudioSample(data: raw.bindMemory(to: UInt8.self).baseAddress!, frames: frames, channels: Int(channels),
                                           rate: rate, pts: start, format: formatDescription)
                  }) else { return }
            enqueueAudio(sample, sec: start, duration: Double(frames) / Double(rate), serial: mySerial)
        }

        func present(_ f: UnsafeMutablePointer<AVFrame>) {
            guard let ctx, f.pointee.sample_rate > 0 else { return }
            let outChannels = ffs_output_channels(f.pointee.ch_layout.nb_channels)
            var data: UnsafePointer<UInt8>?
            let count = ffs_resample(resampler, f, outChannels, &data)
            guard count > 0, let data else { return }
            #if DEBUG
            if Self.logAudioLevel { meter.add(data, frames: Int(count), channels: Int(outChannels), rate: f.pointee.sample_rate) }
            #endif

            let rate = f.pointee.sample_rate
            let tb = ctx.pointee.pkt_timebase.num > 0 ? ctx.pointee.pkt_timebase : AVRational(num: 1, den: rate)
            var pts = f.pointee.best_effort_timestamp
            if pts == ffs_nopts() { pts = f.pointee.pts }
            var sec = pts != ffs_nopts() ? Double(pts) * av_q2d(tb) : (nextPTS ?? 0)
            // Containers with millisecond timestamps (MKV) round short frames – TrueHD's 40-sample
            // frames last 0.83 ms – so consecutive buffers would overlap and the renderer drops the
            // audio. Small deviations follow the sample count; only real jumps resync.
            if let expected = nextPTS, abs(sec - expected) < 0.05 { sec = expected }
            let duration = Double(count) / Double(rate)
            let continues = blockFrames > 0 && blockKey == (rate, outChannels)
                && abs(sec - (blockStart + Double(blockFrames) / Double(rate))) < 0.001
            if !continues {
                sendBlock()
                blockStart = sec
                blockKey = (rate, outChannels)
            }
            nextPTS = sec + duration
            block.append(data, count: Int(count) * Int(outChannels) * 4)
            blockFrames += Int(count)
            if blockFrames >= Int(rate) / 50 { sendBlock() }
        }

        func decode(_ pkt: UnsafeMutablePointer<AVPacket>?) {
            guard let ctx else { return }
            var sent = avcodec_send_packet(ctx, pkt)
            while true {
                while avcodec_receive_frame(ctx, frame) >= 0 {
                    present(frame)
                    av_frame_unref(frame)
                }
                guard sent == ffs_error_eagain() else { break }
                sent = avcodec_send_packet(ctx, pkt)
            }
        }

        ensureDecoder()
        while !isStopped {
            guard let item = audioQ.get() else { break }
            switch item {
            case .flush(let s):
                mySerial = s
                ensureDecoder()
                if let ctx { avcodec_flush_buffers(ctx) }
                nextPTS = nil
                block.removeAll(keepingCapacity: true)
                blockFrames = 0
                audioSink?.flush()
                audioRefillRequested = false
            case .eof(let s):
                guard s == mySerial else { continue }
                decode(nil)
                sendBlock()
                if let ctx { avcodec_flush_buffers(ctx) }
                lock.lock()
                audioDrained = true
                lock.unlock()
            case .packet(let pkt, let s):
                if s == mySerial { decode(pkt) }
                var p: UnsafeMutablePointer<AVPacket>? = pkt
                av_packet_free(&p)
            }
        }
    }

    #if DEBUG
    /// IPTV_AUDIOLEVEL=1: logs the peak level per channel once per second ("no sound" reports).
    private static let logAudioLevel = ProcessInfo.processInfo.environment["IPTV_AUDIOLEVEL"] == "1"

    private final class AudioLevelMeter {
        private var peaks: [Float] = []
        private var frames = 0

        func add(_ data: UnsafePointer<UInt8>, frames count: Int, channels: Int, rate: Int32) {
            if peaks.count != channels { peaks = Array(repeating: 0, count: channels) }
            data.withMemoryRebound(to: Float.self, capacity: count * channels) { samples in
                for i in 0..<(count * channels) { peaks[i % channels] = max(peaks[i % channels], abs(samples[i])) }
            }
            frames += count
            guard frames >= Int(rate) else { return }
            let db = peaks.map { $0 > 0 ? String(format: "%.0f", 20 * log10($0)) : "-inf" }.joined(separator: " ")
            debugLog("[test] audio peak dB [\(db)]")
            peaks = Array(repeating: 0, count: channels)
            frames = 0
        }
    }
    #endif

    private func enqueueAudio(_ sample: CMSampleBuffer, sec: Double, duration: Double, serial s: Int) {
        while true {
            lock.lock()
            if stopped || s != serial {
                lock.unlock()
                return
            }
            if prerolling {
                if startTime == nil {
                    if firstAudioPTS == nil { firstAudioPTS = sec }
                    if hasVideo {
                        // Let the first video frame define the start; audio before it is dropped.
                        lock.unlock()
                        Thread.sleep(forTimeInterval: 0.005)
                        continue
                    }
                    startTime = max(sec, prerollTarget ?? sec)
                }
                let start = startTime!
                if sec + duration <= start {
                    lock.unlock()
                    return
                }
                if audioEnqueuedUntil == -.infinity && sec > start + 0.3 { audioStartsLater = true }
                let ahead = sec - start
                lock.unlock()
                if ahead > 1.0 {
                    Thread.sleep(forTimeInterval: 0.005)
                    continue
                }
            } else {
                lock.unlock()
                let now = sync.currentTime().seconds
                if sec - now > 1.0 {
                    Thread.sleep(forTimeInterval: 0.01)
                    continue
                }
            }
            // Paced above (at most 1 s ahead), so the queue stays short without readiness checks.
            if case .suggestsFlush? = audioSink?.enqueue(sample), !audioRefillRequested {
                audioRefillRequested = true
                emit(.audioNeedsRefill)
            }
            lock.lock()
            audioEnqueuedUntil = max(audioEnqueuedUntil, sec + duration)
            lock.unlock()
            return
        }
    }

    private static func makeAudioFormat(rate: Int32, channels: Int32) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels) * 4, mFramesPerPacket: 1, mBytesPerFrame: UInt32(channels) * 4,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var layout = AudioChannelLayout()
        // FFmpeg's default 5.1 order is L R C LFE Ls Rs.
        layout.mChannelLayoutTag = channels == 6 ? kAudioChannelLayoutTag_MPEG_5_1_A : kAudioChannelLayoutTag_Stereo
        var fd: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: MemoryLayout<AudioChannelLayout>.size,
                                       layout: &layout, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &fd)
        return fd
    }

    private static func makeAudioSample(data: UnsafePointer<UInt8>, frames: Int, channels: Int, rate: Int32,
                                        pts: Double, format: CMAudioFormatDescription) -> CMSampleBuffer? {
        let length = frames * channels * 4
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: length,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block,
              CMBlockBufferReplaceDataBytes(with: data, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) == noErr
        else { return nil }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue((pts * Double(rate)).rounded()), timescale: rate),
            packetDescriptions: nil, sampleBufferOut: &sample)
        return sample
    }

    // MARK: - Monitor (clock, buffering, end of stream)

    private func startMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "player.monitor", qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.tick() }
        monitor = timer
        timer.resume()
    }

    private var tickCount = 0
    private var audioGapSince: Date?
    private var audioGapShown = false

    private func tick() {
        let now = sync.currentTime().seconds
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        tickCount += 1
        var events: [Event] = []

        if prerolling {
            let elapsed = Date().timeIntervalSince(prerollStartedAt)
            if startTime == nil, elapsed > 6, let first = firstAudioPTS {
                startTime = max(first, prerollTarget ?? first)
            }
            if let start = startTime {
                let videoReady = !hasVideo || videoEnqueuedUntil > start || videoDrained || elapsed > 6
                // A declared audio track that never delivers packets must not hold the picture back.
                let audioSilent = elapsed > 2.5 && audioDemuxedUntil == -.infinity
                let audioReady = !hasAudio || audioEnqueuedUntil >= start + 0.3 || audioDrained || audioSilent
                    || audioStartsLater || elapsed > 8
                if videoReady && audioReady {
                    prerolling = false
                    buffering = false
                    if stats.startupTime == 0 { stats.startupTime = Date().timeIntervalSince(createdAt) }
                    sync.setRate(userPaused ? 0 : 1, time: CMTime(sec: start))
                    events.append(.started)
                }
            }
        } else if !userPaused {
            if !buffering {
                // Live: when only audio runs dry but the picture still has data, keep the picture
                // going and let audio rejoin on its timestamps (some restreams burst audio).
                let videoHasData = hasVideo && videoDemuxedUntil - now > 0.5
                let audioLow = hasAudio && !audioDrained && audioEnqueuedUntil.isFinite && audioEnqueuedUntil < now + 0.04
                    && !(liveTimeline && videoHasData)
                let videoLow = !hasAudio && hasVideo && !videoDrained && videoEnqueuedUntil < now
                if (audioLow || videoLow) && !eof {
                    buffering = true
                    rebuffers += 1
                    sync.rate = 0
                    events.append(.buffering(true))
                }
            } else {
                var ahead = min(hasVideo ? videoDemuxedUntil : .infinity, hasAudio ? audioDemuxedUntil : .infinity) - now
                // Live: audio that delivers nothing must not hold the picture; it rejoins on its
                // timestamps (same rule as the underrun check above).
                if liveTimeline && hasVideo && hasAudio && audioDemuxedUntil <= now { ahead = videoDemuxedUntil - now }
                if ahead >= (liveTimeline ? 1.5 : 2.5) || eof {
                    buffering = false
                    sync.rate = 1
                    events.append(.buffering(false))
                }
            }
        }

        // Audio gap: playing, audio expected, but nothing queued for "now". Debounced so
        // that sub-second hiccups do not flash the indicator.
        let audioMissing = !prerolling && !userPaused && !buffering && hasAudio && !audioDrained
            && !(audioEnqueuedUntil > now - 0.1)
        if audioMissing {
            if audioGapSince == nil { audioGapSince = Date() }
            if !audioGapShown, let since = audioGapSince, Date().timeIntervalSince(since) > 0.7 {
                audioGapShown = true
                events.append(.audioGap(true))
            }
        } else {
            audioGapSince = nil
            if audioGapShown {
                audioGapShown = false
                events.append(.audioGap(false))
            }
        }

        let drained = (!hasVideo || videoDrained) && (!hasAudio || audioDrained)
        if eof && drained && !prerolling && !endedSent && now >= max(videoEnqueuedUntil, audioEnqueuedUntil) - 0.05 {
            endedSent = true
            events.append(.ended)
        }

        if tickCount % 2 == 0 && !prerolling {
            let demuxed = min(hasVideo ? videoDemuxedUntil : .infinity, hasAudio ? audioDemuxedUntil : .infinity)
            events.append(.position(now - timeOffset, buffered: demuxed.isFinite ? demuxed - timeOffset : 0))
        }

        if isLive && tickCount % 4 == 0 {
            let demuxed = min(hasVideo ? videoDemuxedUntil : .infinity, hasAudio ? audioDemuxedUntil : .infinity)
            let ahead = prerolling || buffering || !demuxed.isFinite ? 0 : max(0, demuxed - now)
            source.reportPlaybackAhead(ahead)
        }

        if tickCount % 20 == 0 {
            let t = Date()
            let interval = t.timeIntervalSince(lastStatsAt)
            let bytes = source.totalBytesReceived
            stats.frameRate = Double(framesPresented - lastStatsFrames) / interval
            stats.bitrateMbps = Double(bytes - lastStatsBytes) * 8 / interval / 1_000_000
            let demuxed = min(hasVideo ? videoDemuxedUntil : .infinity, hasAudio ? audioDemuxedUntil : .infinity)
            stats.bufferSeconds = demuxed.isFinite ? max(0, demuxed - now) : 0
            stats.droppedFrames = lateDrops
            stats.decodeFailures = decodeFailures
            stats.audioAhead = audioEnqueuedUntil.isFinite ? audioEnqueuedUntil - now : -1
            let net = source.netStats
            stats.networkBufferBytes = net.unreadBytes
            stats.connectTime = net.connectTime
            stats.seamlessReconnects = net.reconnects
            stats.isReconnecting = net.isReconnecting
            stats.lastReconnectReason = net.lastReconnectReason
            stats.lastReconnectAt = net.lastReconnectAt
            stats.rebuffers = rebuffers
            stats.duplicatesDropped = duplicatesDropped
            lastStatsAt = t
            lastStatsFrames = framesPresented
            lastStatsBytes = bytes
            events.append(.stats(stats))

        }
        lock.unlock()

        for event in events { emit(event) }
    }

    #if DEBUG
    /// IPTV_TESTNODATA=<offline|silent>:<s>: for that many seconds after the first tuner
    /// connection, tuner connections fail as an offline channel, or (silent) deliver nothing and
    /// time out after 8 s – a recording has to keep waiting for its channel.
    private static let noDataTest: (offline: Bool, until: Date)? = {
        let parts = ProcessInfo.processInfo.environment["IPTV_TESTNODATA"]?.split(separator: ":") ?? []
        guard parts.count == 2, let seconds = Double(parts[1]) else { return nil }
        return (parts[0] == "offline", Date().addingTimeInterval(seconds))
    }()

    private func simulateNoData() throws {
        guard isTuner, let test = Self.noDataTest, Date() < test.until else { return }
        debugLog("[test] simulating a channel without data (\(test.offline ? "offline" : "silent"))")
        if test.offline { throw PlayerError.offline }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && !isStopped { Thread.sleep(forTimeInterval: 0.1) }
        throw HTTPByteSource.SourceError.timeout
    }

    /// IPTV_TESTNET="drop:15,stall:40,close:60": kill the connection / stall the socket / end the
    /// download as if the server had closed it cleanly, at those seconds after start – the live
    /// reconnect and, for films, continuing an interrupted download. "forbid:<s>": the next
    /// reconnect to the edge gets a 403; "flaky:<s>": drops now and 6 s after the reconnect;
    /// "trickle:<s>": the connection delivers only IPTV_TRICKLEKBIT kbit/s (default 300) until the
    /// next reconnect.
    private func scheduleNetworkTest() {
        guard let spec = ProcessInfo.processInfo.environment["IPTV_TESTNET"] else { return }
        for item in spec.split(separator: ",") {
            let parts = item.split(separator: ":")
            guard parts.count == 2, let at = Double(parts[1]) else { continue }
            let kind = String(parts[0])
            DispatchQueue.global().asyncAfter(deadline: .now() + at) { [weak self] in
                guard let self, !self.isStopped else { return }
                debugLog("[test] simulating network \(kind)")
                guard let http = self.source as? HTTPByteSource else { return }
                switch kind {
                case "drop": http.debugDropConnection()
                case "close": http.debugCloseConnection()
                case "forbid": http.debugForbidNextEdge()
                case "flaky": http.debugFlakyEdge()
                case "trickle":
                    let kbit = ProcessInfo.processInfo.environment["IPTV_TRICKLEKBIT"].flatMap(Double.init) ?? 300
                    http.debugTrickle(kbit: kbit)
                default: http.debugStallConnection()
                }
            }
        }
    }
    #endif

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

/// The newest video frame sent to the renderer (the renderer itself does not hand it out while
/// it plays): Picture in Picture starts only with a picture, and its loading picture is based on it.
final class LastPicture: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    var value: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func set(_ buffer: CVPixelBuffer?) {
        lock.lock()
        self.buffer = buffer
        lock.unlock()
    }
}

enum PlayerError: LocalizedError {
    case message(String)
    case offline
    /// The tuner cannot remux these streams (timeshift unavailable).
    case unsupported
    /// Debug builds stream only from the demo server or a local test server, so a test never
    /// takes the stream slot of the developer's own account (`IPTV_ALLOWREAL=1` lifts it).
    case debugRealProvider

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .offline: return String(localized: "Der Sender ist beim Anbieter derzeit offline.")
        case .unsupported: return String(localized: "Zeitversetztes Fernsehen ist für diesen Sender nicht möglich.")
        case .debugRealProvider: return String(localized: "Debug-Build: echte Anbieter nur mit IPTV_ALLOWREAL=1")
        }
    }

    #if DEBUG
    /// Xtream stream URLs (live, films, episodes, catch-up) of other servers are refused;
    /// Jellyfin and local files are not Xtream streams and pass.
    static func debugAllows(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.scheme?.hasPrefix("http") == true else { return true }
        let xtream = ["live", "movie", "series", "timeshift"].contains(url.pathComponents.dropFirst().first ?? "")
        guard xtream else { return true }
        if ["fernsy-demo.mobilistics.workers.dev", "127.0.0.1", "localhost"].contains(host) { return true }
        if ProcessInfo.processInfo.environment["IPTV_ALLOWREAL"] == "1" { return true }
        AppLog.error(.player, "debug build refused a stream from \(host) (IPTV_ALLOWREAL=1 allows it)")
        return false
    }
    #endif
}
