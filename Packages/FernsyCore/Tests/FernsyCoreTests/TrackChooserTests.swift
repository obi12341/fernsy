import Testing
@testable import FernsyCore

/// Audio and subtitle choice from the user's track settings (playback spec, track choice).
struct TrackChooserTests {
    static let audio = [MediaTrack(id: 1, title: "de", language: "de", isDefault: true),
                        MediaTrack(id: 2, title: "en", language: "en")]
    static let subs = [MediaTrack(id: 3, title: "de forced", language: "de", isForced: true, isDefault: true),
                       MediaTrack(id: 4, title: "de", language: "de"),
                       MediaTrack(id: 5, title: "en", language: "en"),
                       MediaTrack(id: 6, title: "en forced", language: "en", isForced: true)]

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let preferences: TrackPreferences
        var audio = TrackChooserTests.audio
        var subtitles = TrackChooserTests.subs
        let expected: (audio: Int32?, subtitle: Int32?)
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "audio en, subtitles off", preferences: .init(audioLanguage: "en", subtitles: .off), expected: (2, nil)),
        Case(name: "audio fr missing → default", preferences: .init(audioLanguage: "fr", subtitles: .off), expected: (1, nil)),
        Case(name: "no default → first", preferences: .init(audioLanguage: "fr", subtitles: .off),
             audio: [audio[1], MediaTrack(id: 7, title: "x")], expected: (2, nil)),
        Case(name: "en audio + de subtitles → full de", preferences: .init(audioLanguage: "en", subtitles: .language("de")), expected: (2, 4)),
        Case(name: "de audio + de subtitles → forced de", preferences: .init(audioLanguage: "de", subtitles: .language("de")), expected: (1, 3)),
        Case(name: "forced only, de audio", preferences: .init(audioLanguage: "de", subtitles: .forcedOnly), expected: (1, 3)),
        Case(name: "forced only, en audio", preferences: .init(audioLanguage: "en", subtitles: .forcedOnly), expected: (2, 6)),
        Case(name: "forced only, none in audio language", preferences: .init(audioLanguage: "en", subtitles: .forcedOnly),
             subtitles: Array(subs.prefix(2)), expected: (2, nil)),
        Case(name: "fr subtitles missing → off", preferences: .init(audioLanguage: "de", subtitles: .language("fr")), expected: (1, nil)),
        Case(name: "only forced in language → forced", preferences: .init(audioLanguage: "en", subtitles: .language("de")),
             subtitles: [subs[0]], expected: (2, 3)),
        Case(name: "full de with de audio → full de", preferences: .init(audioLanguage: "de", subtitles: .full("de")), expected: (1, 4)),
        Case(name: "de audio + de subtitles, no forced → off", preferences: .init(audioLanguage: "de", subtitles: .language("de")),
             subtitles: [subs[1]], expected: (1, nil)),
    ]

    @Test(arguments: cases)
    func choose(_ c: Case) {
        let got = TrackChooser.choose(audio: c.audio, subtitles: c.subtitles, preferences: c.preferences)
        #expect(got.audio == c.expected.audio)
        #expect(got.subtitle == c.expected.subtitle)
    }
}
