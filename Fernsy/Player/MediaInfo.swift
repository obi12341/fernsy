import CoreGraphics
import Foundation

struct MediaTrack: Identifiable, Hashable {
    let id: Int32
    let title: String
    /// ISO 639-1 code ("de"), nil when the stream has none.
    var language: String? = nil
    /// Forced subtitles: only the foreign-language parts of a dub.
    var isForced = false
    var isDefault = false
}

struct MediaInfo: Equatable {
    var duration: Double?
    var isLive: Bool
    var hasVideo: Bool
    var hasAudio: Bool
    var audioTracks: [MediaTrack]
    var subtitleTracks: [MediaTrack]
    var selectedAudio: Int32?
    var selectedSubtitle: Int32?
}

struct PlaybackStats: Equatable {
    var container = ""
    var videoCodec = ""
    var resolution = ""
    var frameRate = 0.0
    var pixelFormat = ""
    var decoder = ""
    var deinterlace = ""
    var dynamicRange = ""
    var audio = ""
    var bufferSeconds = 0.0
    var bitrateMbps = 0.0
    var droppedFrames = 0
    /// Frames the video renderer could not decode.
    var decodeFailures = 0
    /// Seconds of decoded audio queued in the renderer ahead of the clock.
    var audioAhead = 0.0
    /// Received from the network but not yet demuxed.
    var networkBufferBytes = 0
    /// Request to response headers of the latest connection.
    var connectTime = 0.0
    /// Open to first frame of this session.
    var startupTime = 0.0
    var rebuffers = 0
    /// Live connections replaced without interrupting playback.
    var seamlessReconnects = 0
    var isReconnecting = false
    var lastReconnectReason: String?
    var lastReconnectAt: Date?
    /// Packets dropped at reconnect junctions because they had already been played.
    var duplicatesDropped = 0
    /// Full player restarts (set by PlayerEngine).
    var restarts = 0
    /// Jellyfin: "Direct play" or "Transcode" (set by PlayerEngine).
    var playMethod: String?
    /// Timeshift (set by PlayerEngine): seconds kept on disk, and stored ahead of the player.
    var timeshiftStored: Double?
    var timeshiftAhead: Double?
}

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

/// A bitmap subtitle (PGS, VobSub, DVB): pictures placed on a canvas of the subtitle's own size.
struct BitmapCue {
    struct Piece {
        let image: CGImage
        /// In canvas pixels.
        let rect: CGRect
    }

    let id = UUID()
    var start: Double
    /// `.infinity` until the next cue ends it.
    var end: Double
    let pieces: [Piece]
    /// Size the rects refer to; zero = use the video size.
    let canvas: CGSize

    var images: [Piece] { pieces }
}

enum MediaNames {
    static func videoCodec(_ id: AVCodecID) -> String {
        let name = String(cString: avcodec_get_name(id))
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

    static func audioCodec(_ id: AVCodecID) -> String {
        let name = String(cString: avcodec_get_name(id))
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

    static func channels(_ n: Int32) -> String {
        switch n {
        case 0: return "–"
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return String(localized: "\(Int(n)) audio channels")
        }
    }

    private static let bibliographic: [String: String] = [
        "ger": "de", "fre": "fr", "dut": "nl", "chi": "zh", "cze": "cs", "gre": "el", "per": "fa",
        "rum": "ro", "slo": "sk", "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "geo": "ka",
        "ice": "is", "mac": "mk", "mao": "mi", "may": "ms", "tib": "bo", "wel": "cy",
    ]

    /// Two-letter code for a stream's language tag ("deu", "ger", "de" → "de"), nil for none/"und".
    static func languageCode(_ code: String?) -> String? {
        guard let code = code?.lowercased(), !code.isEmpty, code != "und" else { return nil }
        let normalized = bibliographic[code] ?? code
        return Locale.LanguageCode(normalized).identifier(.alpha2) ?? normalized
    }

    /// Many files mark forced subtitles only in the title ("German Forced", "FORCED SRT").
    static func titleSaysForced(_ title: String?) -> Bool {
        guard let title = title?.lowercased() else { return false }
        return title.contains("forced") || title.contains("erzwungen")
    }

    static func language(_ code: String?) -> String? {
        guard let code, !code.isEmpty, code != "und" else { return nil }
        let normalized = bibliographic[code.lowercased()] ?? code.lowercased()
        return Locale.current.localizedString(forLanguageCode: normalized) ?? code
    }
}
