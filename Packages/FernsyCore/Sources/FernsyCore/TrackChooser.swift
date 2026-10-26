import Foundation

/// Which audio language and subtitles a playback starts with: the settings, or what the user
/// picked for the series last time.
public struct TrackPreferences: Codable, Equatable, Sendable {
    public enum Subtitles: Codable, Equatable, Sendable {
        case off
        case forcedOnly
        case language(String)
        /// The full track in that language even when the audio is in it too – only remembered
        /// from a pick in the player, not offered in the settings.
        case full(String)
    }

    /// ISO 639-1 code; nil = the system language.
    public var audioLanguage: String?
    public var subtitles: Subtitles = .off

    public static let audioKey = "tracks.audioLanguage"
    public static let subtitlesKey = "tracks.subtitles"

    /// The settings ("Sprache & Untertitel"); debug runs can override them without touching
    /// the stored values (IPTV_AUDIOLANG=<code|system>, IPTV_SUBTITLES=<off|forced|code>).
    public static var settings: TrackPreferences {
        let defaults = UserDefaults.standard
        var audio = defaults.string(forKey: audioKey) ?? ""
        var subtitles = defaults.string(forKey: subtitlesKey) ?? "off"
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let value = env["IPTV_AUDIOLANG"] { audio = value == "system" ? "" : value }
        if let value = env["IPTV_SUBTITLES"] { subtitles = value }
        #endif
        return TrackPreferences(audioLanguage: audio.isEmpty ? nil : audio, subtitles: Subtitles(stored: subtitles))
    }

    /// The audio language the chooser looks for.
    public var effectiveAudioLanguage: String? {
        audioLanguage ?? Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier(.alpha2) ?? $0 }
    }

    public init(audioLanguage: String? = nil, subtitles: Subtitles = .off) {
        self.audioLanguage = audioLanguage
        self.subtitles = subtitles
    }
}

extension TrackPreferences.Subtitles {
    public init(stored: String) {
        switch stored {
        case "off", "": self = .off
        case "forced": self = .forcedOnly
        case let value where value.hasPrefix("full:"): self = .full(String(value.dropFirst(5)))
        default: self = .language(stored)
        }
    }

    public var stored: String {
        switch self {
        case .off: return "off"
        case .forcedOnly: return "forced"
        case .language(let code): return code
        case .full(let code): return "full:" + code
        }
    }
}

/// What a new session starts with: the language rules, or tracks already decided (a controller
/// such as Jellyfin playback, or the user's pick when the engine restarts the stream).
public enum TrackRequest: Equatable, Sendable {
    case preferences(TrackPreferences)
    case explicit(audio: Int32?, subtitle: Int32?)
}

/// The same rules for every source: IPTV streams, recordings and Jellyfin items.
public enum TrackChooser: Sendable {
    public static func choose(audio: [MediaTrack], subtitles: [MediaTrack],
                       preferences: TrackPreferences) -> (audio: Int32?, subtitle: Int32?) {
        let audioTrack = chooseAudio(audio, language: preferences.effectiveAudioLanguage)
        let subtitle = chooseSubtitle(subtitles, mode: preferences.subtitles, audioLanguage: audioTrack?.language)
        return (audioTrack?.id, subtitle?.id)
    }

    /// Language match (the default-flagged one among several), else the default track, else the first.
    public static func chooseAudio(_ tracks: [MediaTrack], language: String?) -> MediaTrack? {
        let matching = tracks.filter { language != nil && $0.language == language }
        return matching.first { $0.isDefault } ?? matching.first ?? tracks.first { $0.isDefault } ?? tracks.first
    }

    public static func chooseSubtitle(_ tracks: [MediaTrack], mode: TrackPreferences.Subtitles, audioLanguage: String?) -> MediaTrack? {
        switch mode {
        case .off:
            return nil
        case .forcedOnly:
            guard let audioLanguage else { return nil }
            return best(tracks.filter { $0.isForced && $0.language == audioLanguage })
        case .language(let language):
            let inLanguage = tracks.filter { $0.language == language }
            // Audio already in that language: only the foreign-language parts need subtitles.
            if audioLanguage == language { return best(inLanguage.filter(\.isForced)) }
            return best(inLanguage.filter { !$0.isForced }) ?? best(inLanguage.filter(\.isForced))
        case .full(let language):
            let inLanguage = tracks.filter { $0.language == language }
            return best(inLanguage.filter { !$0.isForced }) ?? best(inLanguage)
        }
    }

    private static func best(_ tracks: [MediaTrack]) -> MediaTrack? {
        tracks.first { $0.isDefault } ?? tracks.first
    }
}
