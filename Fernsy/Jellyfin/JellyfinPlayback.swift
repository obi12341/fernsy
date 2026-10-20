import Combine
import Foundation
import VideoToolbox

/// Plays one Jellyfin film or episode in the player engine: direct play from the original file
/// when Fernsy can play it, otherwise (or when opening fails) a progressive transcode by the
/// server. Reports start, progress and stop to Jellyfin.
@MainActor
final class JellyfinPlayback: ObservableObject {
    enum Method { case direct, transcode }

    let item: JFItem
    @Published private(set) var nextEpisode: JFItem?
    private(set) var method: Method = .direct

    private let store: JellyfinStore
    private let engine: PlayerEngine
    private let source: JFMediaSource
    private var playSessionId: String?
    /// Jellyfin stream indices of the current choice (nil audio = the player's default).
    private var audioIndex: Int?
    private var subtitleIndex: Int?
    private var fellBack = false
    /// Text subtitles fetched from the server, kept for stream restarts.
    private var loadedCues: (index: Int, cues: [SubtitleCue])?
    private var reportedStart = false
    private var stopped = false
    private var timer: Timer?
    private var observers: Set<AnyCancellable> = []

    /// Container of the progressive transcode.
    static var transcodeContainer = "mkv"
    /// Track ids for files the stream does not contain: external text and bitmap subtitles.
    private static let externalTextBase: Int32 = 10_000
    private static let externalBitmapBase: Int32 = 20_000

    private init(item: JFItem, source: JFMediaSource, store: JellyfinStore, engine: PlayerEngine) {
        self.item = item
        self.source = source
        self.store = store
        self.engine = engine
    }

    /// Loads the item's media information and prepares playback.
    static func make(itemId: String, store: JellyfinStore, engine: PlayerEngine) async -> JellyfinPlayback? {
        await store.loadDetail(itemId)
        guard let item = store.details[itemId], let source = item.mediaSources?.first else { return nil }
        return JellyfinPlayback(item: item, source: source, store: store, engine: engine)
    }

    private var streams: [JFMediaStream] { source.mediaStreams ?? [] }

    /// Jellyfin numbers external files first and the file's own streams after them; FFmpeg
    /// numbers only the file's streams, from 0. The n-th embedded stream is FFmpeg stream n.
    private var embeddedIndices: [Int] { streams.filter { $0.isExternal != true }.compactMap(\.index).sorted() }

    private func jellyfinIndex(ofStream id: Int32) -> Int? {
        let embedded = embeddedIndices
        return embedded.indices.contains(Int(id)) ? embedded[Int(id)] : nil
    }

    private func streamId(ofJellyfin index: Int) -> Int32? {
        embeddedIndices.firstIndex(of: index).map(Int32.init)
    }
    private var mediaSourceId: String { source.id ?? item.id }
    private var duration: Double? { (source.runTimeTicks ?? item.runTimeTicks).map { Double($0) / 10_000_000 } }

    // MARK: Decision

    /// Why Fernsy cannot play the original itself, or nil.
    var transcodeReason: String? {
        guard let video = streams.first(where: { $0.type == "Video" }) else { return nil }
        // Profile 5 has no HDR10/SDR base layer: without a Dolby Vision decoder the colours are wrong.
        if video.videoRangeType == "DOVI" && !DVDecoder.isAvailable { return "Dolby Vision Profil 5" }
        let codec = (video.codec ?? "").lowercased()
        if codec == "av1" && !VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) { return "AV1 ohne Hardware-Decoder" }
        if !codec.isEmpty && avcodec_find_decoder_by_name(codec) == nil { return "Codec \(codec)" }
        return nil
    }

    // MARK: Start and stop

    /// The language rules over all of the item's streams, external files included (the player
    /// only sees the file's own streams). Sets the Jellyfin indices the playback starts with.
    private func chooseTracks() {
        let audio = streams.filter { $0.type == "Audio" }.compactMap { s in s.index.map { s.track(id: Int32($0)) } }
        let subtitles = streams.filter { $0.type == "Subtitle" }.compactMap { s in s.index.map { s.track(id: Int32($0)) } }
        let choice = TrackChooser.choose(audio: audio, subtitles: subtitles, preferences: engine.trackPreferences)
        audioIndex = choice.audio.map(Int.init)
        subtitleIndex = choice.subtitle.map(Int.init)
        #if DEBUG
        debugLog("[jellyfin] tracks: audio \(audioIndex.map(String.init) ?? "-"), subtitle \(subtitleIndex.map(String.init) ?? "-")")
        #endif
    }

    func start(at position: Double) {
        observeEngine()
        chooseTracks()
        if let reason = transcodeReason {
            #if DEBUG
            debugLog("[jellyfin] transcode: \(reason)")
            #endif
            startTranscode(at: position)
        } else if let subtitleIndex, let stream = streams.first(where: { $0.index == subtitleIndex }),
                  stream.isExternal == true, stream.isTextSubtitleStream != true {
            // An external bitmap file only reaches the picture as a burn-in.
            startTranscode(at: position)
        } else {
            startDirect(at: position)
        }
        if item.type == "Episode", let seriesId = item.seriesId, let client = store.client, let userId = store.session?.userId {
            Task { nextEpisode = try? await client.nextEpisode(userId: userId, seriesId: seriesId, after: item.id) }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        timer?.invalidate()
        observers.removeAll()
        let ended = engine.status == .ended
        let position = ended ? (duration ?? engine.progress.position) : engine.progress.position
        report(.stopped, position: position)
        if method == .transcode, let client = store.client {
            let session = playSessionId
            Task { await client.stopTranscode(playSessionId: session) }
        }
        let store = store, id = item.id
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await store.refreshAfterPlayback(id)
        }
    }

    private func startDirect(at position: Double) {
        guard var url = store.client?.directStreamURL(itemId: item.id, mediaSourceId: mediaSourceId) else { return }
        #if DEBUG
        // Tests the fallback: the altered path answers 404, so opening fails.
        if ProcessInfo.processInfo.environment["JF_BREAKDIRECT"] == "1", !fellBack,
           var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.path += "-broken"
            url = c.url ?? url
        }
        #endif
        method = .direct
        var external = ExternalPlayback()
        external.methodLabel = String(localized: "Direkt (Originaldatei)")
        external.onFailedBeforeStart = { [weak self] message in
            guard let self, !self.fellBack else { return false }
            self.fellBack = true
            #if DEBUG
            debugLog("[jellyfin] direct play failed (\(message)), falling back to a transcode")
            #endif
            self.startTranscode(at: position)
            return true
        }
        external.selectSubtitle = { [weak self] track in self?.selectSubtitle(track) ?? false }
        external.onOpened = { [weak self] in self?.tracksOpened() }
        let embeddedSubtitle = subtitleIndex.flatMap { index in streams.first { $0.index == index && $0.isExternal != true } }
        external.tracks = .explicit(audio: audioIndex.flatMap(streamId(ofJellyfin:)),
                                    subtitle: embeddedSubtitle?.index.flatMap(streamId(ofJellyfin:)))
        external.selectAudio = { [weak self] track in
            guard let self else { return false }
            self.audioIndex = self.jellyfinIndex(ofStream: track.id)
            self.report(.progress)
            return false
        }
        engine.load(url: url, isLive: false, startAt: position, external: external)
    }

    private func startTranscode(at position: Double) {
        guard let client = store.client, let userId = store.session?.userId else { return }
        method = .transcode
        let previous = playSessionId
        // Text subtitles are shown by the player (from the server's SRT); only bitmap ones are burnt in.
        let burnIn = subtitleIndex.flatMap { index in streams.first { $0.index == index } }.map { $0.isTextSubtitleStream != true } ?? false
        Task {
            if previous != nil { await client.stopTranscode(playSessionId: previous) }
            do {
                let result = try await client.transcode(userId: userId, itemId: item.id, mediaSourceId: mediaSourceId,
                                                        startSeconds: position, audioIndex: audioIndex,
                                                        subtitleIndex: burnIn ? subtitleIndex : nil,
                                                        container: Self.transcodeContainer)
                guard !stopped else { await client.stopTranscode(playSessionId: result.playSessionId); return }
                playSessionId = result.playSessionId
                var external = ExternalPlayback(timelineOffset: position, duration: duration)
                external.methodLabel = String(localized: "Transcoding (Jellyfin)")
                external.restartAt = { [weak self] target in self?.startTranscode(at: target) }
                external.selectAudio = { [weak self] track in
                    guard let self else { return true }
                    self.audioIndex = Int(track.id)
                    self.startTranscode(at: self.engine.progress.position)
                    return true
                }
                external.selectSubtitle = { [weak self] track in self?.selectSubtitle(track) ?? true }
                external.onOpened = { [weak self] in self?.tracksOpened() }
                external.tracks = .explicit(audio: nil, subtitle: nil)
                engine.load(url: result.url, isLive: false, startAt: 0, external: external)
            } catch {
                #if DEBUG
                debugLog("[jellyfin] transcode request failed: \(error.localizedDescription)")
                #endif
                store.lastError = String(localized: "Jellyfin konnte den Titel nicht umwandeln: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Tracks

    /// Builds the subtitle menu additions (external files) once the stream is open, and in a
    /// transcode the source's full track lists.
    private func tracksOpened() {
        guard !stopped else { return }
        let externalTracks: [MediaTrack] = streams.filter { $0.type == "Subtitle" && $0.isExternal == true }.compactMap { s in
            guard let index = s.index else { return nil }
            let base = s.isTextSubtitleStream == true ? Self.externalTextBase : Self.externalBitmapBase
            return s.track(id: base + Int32(index), suffix: " · " + String(localized: "extern"))
        }
        if method == .direct {
            engine.addSubtitleTracks(externalTracks)
            if audioIndex == nil, let selected = engine.media?.selectedAudio { audioIndex = jellyfinIndex(ofStream: selected) }
        } else {
            let audio = streams.filter { $0.type == "Audio" }.compactMap { s in
                s.index.map { s.track(id: Int32($0)) }
            }
            let subs = streams.filter { $0.type == "Subtitle" && $0.isExternal != true }.compactMap { s in
                s.index.map { s.track(id: Int32($0)) }
            } + externalTracks
            let defaultAudio = streams.first { $0.type == "Audio" && $0.isDefault == true }?.index ?? audio.first.map { Int($0.id) }
            engine.setTracks(audio: audio, subtitles: subs, selectedAudio: (audioIndex ?? defaultAudio).map(Int32.init),
                             selectedSubtitle: currentSubtitleTrackId)
        }
        // A new stream starts without the player's own subtitles: show the fetched ones again,
        // or fetch the chosen text track the stream does not carry (external file, transcode).
        if let subtitleIndex, let trackId = currentSubtitleTrackId,
           let stream = streams.first(where: { $0.index == subtitleIndex }), stream.isTextSubtitleStream == true,
           stream.isExternal == true || method == .transcode {
            loadTextSubtitles(index: subtitleIndex, trackId: trackId)
        }
    }

    private var currentSubtitleTrackId: Int32? {
        guard let subtitleIndex, let stream = streams.first(where: { $0.index == subtitleIndex }) else { return nil }
        if stream.isExternal == true {
            return (stream.isTextSubtitleStream == true ? Self.externalTextBase : Self.externalBitmapBase) + Int32(subtitleIndex)
        }
        // Transcodes list the source's tracks by Jellyfin index, direct play by FFmpeg stream.
        return method == .transcode ? Int32(subtitleIndex) : streamId(ofJellyfin: subtitleIndex)
    }

    /// Returns true when handled here (the engine must not switch the stream's own track).
    private func selectSubtitle(_ track: MediaTrack?) -> Bool {
        guard let track else {
            let wasBurntIn = method == .transcode && burntIn
            subtitleIndex = nil
            if wasBurntIn { startTranscode(at: engine.progress.position); return true }
            report(.progress)
            if method == .transcode {
                engine.clearSubtitleSelection()
                return true
            }
            return false
        }
        let id = track.id
        let jellyfinIndex: Int
        if id >= Self.externalBitmapBase { jellyfinIndex = Int(id - Self.externalBitmapBase) }
        else if id >= Self.externalTextBase { jellyfinIndex = Int(id - Self.externalTextBase) }
        else if method == .transcode { jellyfinIndex = Int(id) }
        else if let index = self.jellyfinIndex(ofStream: id) { jellyfinIndex = index }
        else { return false }
        subtitleIndex = jellyfinIndex
        let stream = streams.first { $0.index == jellyfinIndex }
        let isText = stream?.isTextSubtitleStream == true
        if isText && (stream?.isExternal == true || method == .transcode) {
            loadTextSubtitles(index: jellyfinIndex, trackId: id)
            report(.progress)
            return true
        }
        if !isText && (stream?.isExternal == true || method == .transcode) {
            // Bitmap subtitles the stream does not carry: the server burns them in.
            startTranscode(at: engine.progress.position)
            return true
        }
        report(.progress)
        return false // embedded track of the original file: the player decodes it
    }

    private var burntIn: Bool {
        guard let subtitleIndex, let stream = streams.first(where: { $0.index == subtitleIndex }) else { return false }
        return stream.isTextSubtitleStream != true
    }

    private func loadTextSubtitles(index: Int, trackId: Int32) {
        if let loadedCues, loadedCues.index == index {
            engine.showExternalSubtitles(loadedCues.cues, trackId: trackId)
            return
        }
        guard let client = store.client else { return }
        let itemId = item.id, sourceId = mediaSourceId
        Task {
            do {
                let srt = try await client.subtitleSRT(itemId: itemId, mediaSourceId: sourceId, index: index)
                let cues = SRTParser.parse(srt)
                #if DEBUG
                debugLog("[jellyfin] subtitles \(index): \(cues.count) cues")
                #endif
                guard !stopped, subtitleIndex == index else { return }
                loadedCues = (index, cues)
                engine.showExternalSubtitles(cues, trackId: trackId)
            } catch {
                store.lastError = String(localized: "Untertitel konnten nicht geladen werden: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Reporting

    private func observeEngine() {
        engine.$status.removeDuplicates().sink { [weak self] status in
            guard let self, !self.stopped else { return }
            if status == .playing && !self.reportedStart {
                self.reportedStart = true
                self.report(.start)
                self.startTimer()
            }
        }.store(in: &observers)
        engine.$isPaused.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.report(.progress)
        }.store(in: &observers)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.stopped else { return }
                self.report(.progress)
                if self.method == .transcode, let id = self.playSessionId, let client = self.store.client {
                    Task { await client.pingTranscode(playSessionId: id) }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func report(_ event: JellyfinClient.ProgressEvent, position: Double? = nil) {
        guard let client = store.client, reportedStart || event == .start else { return }
        let position = position ?? engine.progress.position
        let item = item.id, source = mediaSourceId, paused = engine.isPaused, transcoding = method == .transcode
        let session = playSessionId, audio = audioIndex, subtitle = subtitleIndex
        Task {
            await client.report(event, itemId: item, mediaSourceId: source, positionSeconds: position, isPaused: paused,
                                transcoding: transcoding, playSessionId: session, audioIndex: audio, subtitleIndex: subtitle)
        }
    }
}

/// Minimal SRT reader for subtitles delivered by the server.
enum SRTParser {
    static func parse(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(parts[0]), let end = seconds(parts[1]) else { continue }
            let body = lines[(timing + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: body)) }
        }
        return cues
    }

    private static func seconds(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2].prefix(6)) else { return nil }
        return h * 3600 + m * 60 + sec
    }
}
