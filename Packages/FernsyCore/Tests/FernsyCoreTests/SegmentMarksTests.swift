import Foundation
import Testing
@testable import FernsyCore

/// The marks rule (jellyfin-media-segments, design 3) with the shapes seen on a real server with
/// Intro Skipper (titles left out; times as found there).
struct SegmentMarksTests {
    private func seg(_ type: String, _ start: Double, _ end: Double) -> JFMediaSegment {
        JFMediaSegment(type: type, startTicks: Int64(start * 10_000_000), endTicks: Int64(end * 10_000_000))
    }

    private func chapter(_ name: String, _ start: Double) -> JFChapter {
        JFChapter(startPositionTicks: Int64(start * 10_000_000), name: name)
    }

    @Test func creditsToTheEnd() {
        let marks = SegmentMarks.make(segments: [seg("Outro", 2458, 2735)], chapters: [], runtime: 2735)
        #expect(marks.credits == .init(start: 2458, reachesEnd: true))
        #expect(marks.skips.isEmpty)
        #expect(!marks.isInCredits(2457))
        #expect(marks.isInCredits(2458))
    }

    /// Credits followed directly by a preview that runs to the end.
    @Test func creditsAndPreviewAreOneBlock() {
        let marks = SegmentMarks.make(segments: [seg("Outro", 1390, 1460), seg("Preview", 1460, 1490)], chapters: [], runtime: 1490)
        #expect(marks.credits == .init(start: 1390, reachesEnd: true))
    }

    /// A 16 s false hit four minutes before the real credits: the card waits for the last one.
    @Test func earlierShortOutroIsIgnored() {
        let marks = SegmentMarks.make(segments: [seg("Intro", 332, 394), seg("Outro", 2559, 2575), seg("Outro", 2746, 2802)],
                                      chapters: [], runtime: 2802)
        #expect(marks.credits == .init(start: 2746, reachesEnd: true))
        #expect(marks.skips == [.init(kind: .intro, start: 332, end: 394)])
    }

    /// Credits that end 26 s before the end of the file: something follows, no countdown.
    @Test func creditsEndingEarlyDoNotReachTheEnd() {
        let marks = SegmentMarks.make(segments: [seg("Outro", 1887, 1904)], chapters: [chapter("Credits", 1887)], runtime: 1930)
        #expect(marks.credits == .init(start: 1887, reachesEnd: false))
    }

    @Test func creditsWithinTheToleranceReachTheEnd() {
        let marks = SegmentMarks.make(segments: [seg("Outro", 2440, 2470)], chapters: [], runtime: 2477)
        #expect(marks.credits?.reachesEnd == true)
    }

    @Test func recapAtTheStartAndIntroMidEpisode() {
        let marks = SegmentMarks.make(segments: [seg("Recap", 0, 38), seg("Intro", 247, 310), seg("Outro", 1661, 1781)],
                                      chapters: [], runtime: 1781)
        #expect(marks.skips == [.init(kind: .recap, start: 0, end: 38), .init(kind: .intro, start: 247, end: 310)])
        #expect(marks.skip(at: 10)?.kind == .recap)
        #expect(marks.skip(at: 38) == nil)
        #expect(marks.skip(at: 100) == nil)
        #expect(marks.skip(at: 250)?.end == 310)
    }

    @Test func onlyAnIntroHasNoCredits() {
        let marks = SegmentMarks.make(segments: [seg("Intro", 0, 50)], chapters: [], runtime: 427)
        #expect(marks.credits == nil)
        #expect(marks.skips.count == 1)
    }

    @Test func creditsChapterWithoutSegments() {
        let marks = SegmentMarks.make(segments: [], chapters: [chapter("Chapter 01", 0), chapter("Credits", 1360)], runtime: 1490)
        #expect(marks.credits == .init(start: 1360, reachesEnd: true))
    }

    @Test func endingChapterFollowedByPreview() {
        let marks = SegmentMarks.make(segments: [], chapters: [chapter("Opening", 0), chapter("Part A", 90), chapter("Ending", 1390),
                                                               chapter("Preview", 1460)], runtime: 1490)
        #expect(marks.credits == .init(start: 1390, reachesEnd: true))
        #expect(marks.skips.isEmpty, "chapters never give skip buttons")
    }

    @Test func creditsChapterFollowedByAScene() {
        let marks = SegmentMarks.make(segments: [], chapters: [chapter("Credits", 1300), chapter("After the credits", 1400)], runtime: 1490)
        #expect(marks.credits == .init(start: 1300, reachesEnd: false))
    }

    @Test func numberedChaptersGiveNothing() {
        let chapters = (0..<7).map { chapter(String(format: "Chapter %02d", $0 + 1), Double($0) * 400) }
        #expect(SegmentMarks.make(segments: [], chapters: chapters, runtime: 3044) == .none)
    }

    /// Opening credits are not the end of the episode.
    @Test func creditsChapterInTheFirstHalfIsIgnored() {
        #expect(SegmentMarks.make(segments: [], chapters: [chapter("Credits", 30), chapter("Story", 120)], runtime: 1500).credits == nil)
    }

    @Test func segmentsWinOverChapters() {
        let marks = SegmentMarks.make(segments: [seg("Outro", 2440, 2477)], chapters: [chapter("Credits", 2400)], runtime: 2477)
        #expect(marks.credits?.start == 2440)
    }

    @Test func noiseAndOutOfRangeSegmentsAreDropped() {
        let marks = SegmentMarks.make(segments: [seg("Intro", 100, 101), seg("Outro", 3000, 3100), seg("Commercial", 500, 600)],
                                      chapters: [], runtime: 2000)
        #expect(marks == .none)
    }

    @Test func introInsideTheCreditsIsNotOffered() {
        let marks = SegmentMarks.make(segments: [seg("Outro", 1300, 1490), seg("Intro", 1400, 1430)], chapters: [], runtime: 1490)
        #expect(marks.skips.isEmpty)
    }

    @Test func withoutRuntimeTheLastBlockReachesTheEnd() {
        #expect(SegmentMarks.make(segments: [seg("Outro", 100, 120)], chapters: [], runtime: nil).credits?.reachesEnd == true)
    }

    @Test func decodesServerAnswers() throws {
        let segments = try JellyfinModelsTests.decode(JFMediaSegmentsPage.self, "media_segments").items
        #expect(segments.map(\.type) == ["Recap", "Intro", "Outro", "Preview"])
        let episode = try JellyfinModelsTests.decode(JFItem.self, "episode_chapters")
        #expect(episode.chapters?.map(\.name) == ["Opening", "Part A", "Ending", "Preview"])
        let marks = SegmentMarks.make(segments: segments, chapters: episode.chapters ?? [],
                                      runtime: episode.runTimeTicks.map { Double($0) / 10_000_000 })
        #expect(marks.credits == .init(start: 1661, reachesEnd: true))
        #expect(marks.skips.map(\.kind) == [.recap, .intro])
    }

    @Test func oldServerWithoutTheEndpointHasNoSegments() throws {
        #expect(try JellyfinClient.segments(from: .failure(JellyfinError.http(404))).isEmpty)
        #expect(throws: JellyfinError.unauthorized) { try JellyfinClient.segments(from: .failure(JellyfinError.unauthorized)) }
        #expect(try JellyfinClient.segments(from: .success(Data(#"{"Items":[],"TotalRecordCount":0,"StartIndex":0}"#.utf8))).isEmpty)
    }

    @Test func testSwitchList() {
        let list = JFMediaSegment.parseTestList("intro:5-20, OUTRO:96-120,bogus,recap:9-3")
        #expect(list == [JFMediaSegment(type: "Intro", startTicks: 50_000_000, endTicks: 200_000_000),
                         JFMediaSegment(type: "Outro", startTicks: 960_000_000, endTicks: 1_200_000_000)])
    }

    @Test func preferencesDefaultsAndStoredValues() throws {
        let defaults = try #require(UserDefaults(suiteName: "SegmentMarksTests-\(UUID().uuidString)"))
        #expect(SegmentPreferences.read(defaults) == SegmentPreferences(autoplayNext: true, skipping: .button))
        defaults.set(false, forKey: SegmentPreferences.autoplayKey)
        defaults.set("auto", forKey: SegmentPreferences.skippingKey)
        #expect(SegmentPreferences.read(defaults) == SegmentPreferences(autoplayNext: false, skipping: .auto))
        defaults.set("bogus", forKey: SegmentPreferences.skippingKey)
        #expect(SegmentPreferences.read(defaults).skipping == .button)
    }
}

/// The rule over answers collected read-only from a real server: `JF_SEGMENT_SAMPLE` names a
/// JSON file of `{label, runtime, segments, chapters}` (kept outside the repo, e.g. the git-ignored
/// `build/`). Skipped without it. Prints how the episodes come out.
struct SegmentMarksSampleTests {
    struct Episode: Decodable {
        var label: String
        var runtime: Double
        var segments: [JFMediaSegment]
        var chapters: [JFChapter]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JF_SEGMENT_SAMPLE"] != nil))
    func sampleFromARealServer() throws {
        let path = try #require(ProcessInfo.processInfo.environment["JF_SEGMENT_SAMPLE"])
        let episodes = try JSONDecoder().decode([Episode].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        var counting = 0, withoutCountdown: [String] = [], noCard: [String] = [], skips = 0, fromChapters = 0
        for episode in episodes {
            let marks = SegmentMarks.make(segments: episode.segments, chapters: episode.chapters, runtime: episode.runtime)
            let lastOutro = episode.segments.filter { $0.type == "Outro" }.map { Double($0.startTicks) / 10_000_000 }.max()
            if let credits = marks.credits {
                if let lastOutro { #expect(credits.start >= lastOutro - 0.001, "\(episode.label): card before the last Outro") }
                else { fromChapters += 1 }
                if credits.reachesEnd { counting += 1 } else { withoutCountdown.append(episode.label) }
            } else {
                noCard.append(episode.label)
            }
            skips += marks.skips.count
        }
        print("segment sample: \(episodes.count) episodes, \(counting) counting cards, \(withoutCountdown.count) cards without countdown, "
              + "\(noCard.count) without card, \(fromChapters) from chapters, \(skips) skip buttons")
        print("without countdown: \(withoutCountdown.joined(separator: ", "))")
        print("without card: \(noCard.joined(separator: ", "))")
    }
}
