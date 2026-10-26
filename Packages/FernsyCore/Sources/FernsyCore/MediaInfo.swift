import CoreGraphics
import Foundation

public struct MediaTrack: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let title: String
    /// ISO 639-1 code ("de"), nil when the stream has none.
    public var language: String? = nil
    /// Forced subtitles: only the foreign-language parts of a dub.
    public var isForced = false
    public var isDefault = false

    public init(id: Int32, title: String, language: String? = nil, isForced: Bool = false, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.language = language
        self.isForced = isForced
        self.isDefault = isDefault
    }
}

public struct MediaInfo: Equatable, Sendable {
    public var duration: Double?
    public var isLive: Bool
    public var hasVideo: Bool
    public var hasAudio: Bool
    public var audioTracks: [MediaTrack]
    public var subtitleTracks: [MediaTrack]
    public var selectedAudio: Int32?
    public var selectedSubtitle: Int32?

    public init(duration: Double? = nil, isLive: Bool, hasVideo: Bool, hasAudio: Bool, audioTracks: [MediaTrack], subtitleTracks: [MediaTrack], selectedAudio: Int32? = nil, selectedSubtitle: Int32? = nil) {
        self.duration = duration
        self.isLive = isLive
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.selectedAudio = selectedAudio
        self.selectedSubtitle = selectedSubtitle
    }
}

public struct PlaybackStats: Equatable, Sendable {
    public var container = ""
    public var videoCodec = ""
    public var resolution = ""
    public var frameRate = 0.0
    public var pixelFormat = ""
    public var decoder = ""
    public var deinterlace = ""
    public var dynamicRange = ""
    public var audio = ""
    public var bufferSeconds = 0.0
    public var bitrateMbps = 0.0
    public var droppedFrames = 0
    /// Frames the video renderer could not decode.
    public var decodeFailures = 0
    /// Seconds of decoded audio queued in the renderer ahead of the clock.
    public var audioAhead = 0.0
    /// Received from the network but not yet demuxed.
    public var networkBufferBytes = 0
    /// Request to response headers of the latest connection.
    public var connectTime = 0.0
    /// Open to first frame of this session.
    public var startupTime = 0.0
    public var rebuffers = 0
    /// Live connections replaced without interrupting playback.
    public var seamlessReconnects = 0
    public var isReconnecting = false
    public var lastReconnectReason: String?
    public var lastReconnectAt: Date?
    /// Packets dropped at reconnect junctions because they had already been played.
    public var duplicatesDropped = 0
    /// Full player restarts (set by PlayerEngine).
    public var restarts = 0
    /// Jellyfin: "Direct play" or "Transcode" (set by PlayerEngine).
    public var playMethod: String?
    /// Timeshift (set by PlayerEngine): seconds kept on disk, and stored ahead of the player.
    public var timeshiftStored: Double?
    public var timeshiftAhead: Double?

    public init(container: String = "", videoCodec: String = "", resolution: String = "", frameRate: Double = 0.0, pixelFormat: String = "", decoder: String = "", deinterlace: String = "", dynamicRange: String = "", audio: String = "", bufferSeconds: Double = 0.0, bitrateMbps: Double = 0.0, droppedFrames: Int = 0, decodeFailures: Int = 0, audioAhead: Double = 0.0, networkBufferBytes: Int = 0, connectTime: Double = 0.0, startupTime: Double = 0.0, rebuffers: Int = 0, seamlessReconnects: Int = 0, isReconnecting: Bool = false, lastReconnectReason: String? = nil, lastReconnectAt: Date? = nil, duplicatesDropped: Int = 0, restarts: Int = 0, playMethod: String? = nil, timeshiftStored: Double? = nil, timeshiftAhead: Double? = nil) {
        self.container = container
        self.videoCodec = videoCodec
        self.resolution = resolution
        self.frameRate = frameRate
        self.pixelFormat = pixelFormat
        self.decoder = decoder
        self.deinterlace = deinterlace
        self.dynamicRange = dynamicRange
        self.audio = audio
        self.bufferSeconds = bufferSeconds
        self.bitrateMbps = bitrateMbps
        self.droppedFrames = droppedFrames
        self.decodeFailures = decodeFailures
        self.audioAhead = audioAhead
        self.networkBufferBytes = networkBufferBytes
        self.connectTime = connectTime
        self.startupTime = startupTime
        self.rebuffers = rebuffers
        self.seamlessReconnects = seamlessReconnects
        self.isReconnecting = isReconnecting
        self.lastReconnectReason = lastReconnectReason
        self.lastReconnectAt = lastReconnectAt
        self.duplicatesDropped = duplicatesDropped
        self.restarts = restarts
        self.playMethod = playMethod
        self.timeshiftStored = timeshiftStored
        self.timeshiftAhead = timeshiftAhead
    }
}

public struct SubtitleCue: Sendable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A bitmap subtitle (PGS, VobSub, DVB): pictures placed on a canvas of the subtitle's own size.
public struct BitmapCue: Sendable {
    public struct Piece: Sendable {
        public let image: CGImage
        /// In canvas pixels.
        public let rect: CGRect

        public init(image: CGImage, rect: CGRect) {
            self.image = image
            self.rect = rect
        }
    }

    public let id = UUID()
    public var start: Double
    /// `.infinity` until the next cue ends it.
    public var end: Double
    public let pieces: [Piece]
    /// Size the rects refer to; zero = use the video size.
    public let canvas: CGSize

    public var images: [Piece] { pieces }

    public init(start: Double, end: Double, pieces: [Piece], canvas: CGSize) {
        self.start = start
        self.end = end
        self.pieces = pieces
        self.canvas = canvas
    }
}

public enum MediaNames: Sendable {
    /// Display name for FFmpeg's codec name ("h264" → "H.264"); the app passes
    /// `avcodec_get_name` (MediaNames+FFmpeg.swift).
    public static func videoCodec(name: String) -> String {
        switch name {
        case "h264": return "H.264"
        case "hevc": return "HEVC"
        case "mpeg2video": return "MPEG-2"
        case "mpeg4": return "MPEG-4"
        case "av1": return "AV1"
        case "vp9": return "VP9"
        default: return name.uppercased()
        }
    }

    public static func audioCodec(name: String) -> String {
        switch name {
        case "eac3": return "E-AC-3"
        case "ac3": return "AC-3"
        case "mp2": return "MP2"
        case "mp3": return "MP3"
        case "aac", "aac_latm": return "AAC"
        case "dts": return "DTS"
        case "truehd": return "TrueHD"
        case "opus": return "Opus"
        case "flac": return "FLAC"
        default: return name.uppercased()
        }
    }

    public static func channels(_ n: Int32) -> String {
        switch n {
        case 0: return "–"
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return String(localized: "\(Int(n)) audio channels", bundle: .module)
        }
    }

    private static let bibliographic: [String: String] = [
        "ger": "de", "fre": "fr", "dut": "nl", "chi": "zh", "cze": "cs", "gre": "el", "per": "fa",
        "rum": "ro", "slo": "sk", "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "geo": "ka",
        "ice": "is", "mac": "mk", "mao": "mi", "may": "ms", "tib": "bo", "wel": "cy",
    ]

    /// Two-letter code for a stream's language tag ("deu", "ger", "de" → "de"), nil for none/"und".
    public static func languageCode(_ code: String?) -> String? {
        guard let code = code?.lowercased(), !code.isEmpty, code != "und" else { return nil }
        let normalized = bibliographic[code] ?? code
        return Locale.LanguageCode(normalized).identifier(.alpha2) ?? normalized
    }

    /// Many files mark forced subtitles only in the title ("German Forced", "FORCED SRT").
    public static func titleSaysForced(_ title: String?) -> Bool {
        guard let title = title?.lowercased() else { return false }
        return title.contains("forced") || title.contains("erzwungen")
    }

    public static func language(_ code: String?) -> String? {
        guard let code, !code.isEmpty, code != "und" else { return nil }
        let normalized = bibliographic[code.lowercased()] ?? code.lowercased()
        return Locale.current.localizedString(forLanguageCode: normalized) ?? code
    }
}
