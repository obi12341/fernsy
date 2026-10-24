import Foundation

/// Which audio language and subtitles a playback starts with: the settings, or what the user
/// picked for the series last time.
struct TrackPreferences: Codable, Equatable {
    enum Subtitles: Codable, Equatable {
        case off
        case forcedOnly
        case language(String)
        /// The full track in that language even when the audio is in it too – only remembered
        /// from a pick in the player, not offered in the settings.
        case full(String)
    }

    /// ISO 639-1 code; nil = the system language.
    var audioLanguage: String?
    var subtitles: Subtitles = .off

    static let audioKey = "tracks.audioLanguage"
    static let subtitlesKey = "tracks.subtitles"

    /// The settings ("Sprache & Untertitel"); debug runs can override them without touching
    /// the stored values (IPTV_AUDIOLANG=<code|system>, IPTV_SUBTITLES=<off|forced|code>).
    static var settings: TrackPreferences {
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
    var effectiveAudioLanguage: String? {
        audioLanguage ?? Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier(.alpha2) ?? $0 }
    }
}

extension TrackPreferences.Subtitles {
    init(stored: String) {
        switch stored {
        case "off", "": self = .off
        case "forced": self = .forcedOnly
        case let value where value.hasPrefix("full:"): self = .full(String(value.dropFirst(5)))
        default: self = .language(stored)
        }
    }

    var stored: String {
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
enum TrackRequest: Equatable {
    case preferences(TrackPreferences)
    case explicit(audio: Int32?, subtitle: Int32?)
}

/// The same rules for every source: IPTV streams, recordings and Jellyfin items.
enum TrackChooser {
    static func choose(audio: [MediaTrack], subtitles: [MediaTrack],
                       preferences: TrackPreferences) -> (audio: Int32?, subtitle: Int32?) {
        let audioTrack = chooseAudio(audio, language: preferences.effectiveAudioLanguage)
        let subtitle = chooseSubtitle(subtitles, mode: preferences.subtitles, audioLanguage: audioTrack?.language)
        return (audioTrack?.id, subtitle?.id)
    }

    /// Language match (the default-flagged one among several), else the default track, else the first.
    static func chooseAudio(_ tracks: [MediaTrack], language: String?) -> MediaTrack? {
        let matching = tracks.filter { language != nil && $0.language == language }
        return matching.first { $0.isDefault } ?? matching.first ?? tracks.first { $0.isDefault } ?? tracks.first
    }

    static func chooseSubtitle(_ tracks: [MediaTrack], mode: TrackPreferences.Subtitles, audioLanguage: String?) -> MediaTrack? {
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

    #if DEBUG
    /// IPTV_TRACKSELFTEST=1: checks the rules on sample track lists and logs the result.
    static func selfTest() {
        let audio = [MediaTrack(id: 1, title: "de", language: "de", isDefault: true),
                     MediaTrack(id: 2, title: "en", language: "en")]
        let subs = [MediaTrack(id: 3, title: "de forced", language: "de", isForced: true, isDefault: true),
                    MediaTrack(id: 4, title: "de", language: "de"),
                    MediaTrack(id: 5, title: "en", language: "en"),
                    MediaTrack(id: 6, title: "en forced", language: "en", isForced: true)]
        func check(_ name: String, _ prefs: TrackPreferences, _ a: [MediaTrack], _ s: [MediaTrack], _ expected: (Int32?, Int32?)) {
            let got = choose(audio: a, subtitles: s, preferences: prefs)
            let ok = got.audio == expected.0 && got.subtitle == expected.1
            debugLog("[test] self-test \(ok ? "pass" : "FAIL") \(name): audio \(got.audio.map(String.init) ?? "-") subtitle \(got.subtitle.map(String.init) ?? "-")")
        }
        check("audio en, subtitles off", .init(audioLanguage: "en", subtitles: .off), audio, subs, (2, nil))
        check("audio fr missing → default", .init(audioLanguage: "fr", subtitles: .off), audio, subs, (1, nil))
        check("no default → first", .init(audioLanguage: "fr", subtitles: .off), [audio[1], MediaTrack(id: 7, title: "x")], subs, (2, nil))
        check("en audio + de subtitles → full de", .init(audioLanguage: "en", subtitles: .language("de")), audio, subs, (2, 4))
        check("de audio + de subtitles → forced de", .init(audioLanguage: "de", subtitles: .language("de")), audio, subs, (1, 3))
        check("forced only, de audio", .init(audioLanguage: "de", subtitles: .forcedOnly), audio, subs, (1, 3))
        check("forced only, en audio", .init(audioLanguage: "en", subtitles: .forcedOnly), audio, subs, (2, 6))
        check("forced only, none in audio language", .init(audioLanguage: "en", subtitles: .forcedOnly), audio, Array(subs.prefix(2)), (2, nil))
        check("fr subtitles missing → off", .init(audioLanguage: "de", subtitles: .language("fr")), audio, subs, (1, nil))
        check("only forced in language → forced", .init(audioLanguage: "en", subtitles: .language("de")), audio, [subs[0]], (2, 3))
        check("full de with de audio → full de", .init(audioLanguage: "de", subtitles: .full("de")), audio, subs, (1, 4))
        check("de audio + de subtitles, no forced → off", .init(audioLanguage: "de", subtitles: .language("de")), audio, [subs[1]], (1, nil))
    }
    #endif
}
