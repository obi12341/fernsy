import Foundation
import Testing
@testable import FernsyCore
@testable import FernsyShared

/// One show at a time per channel (guide-overlapping-listings): what the clean-up keeps of
/// listings that overlap, in the three ways providers send them.
struct EPGOverlapTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
    private func show(_ title: String, _ from: Double, _ to: Double) -> EPGEntry {
        EPGEntry(id: "\(title) \(from)", title: title, description: "", start: at(from), end: at(to))
    }
    private func clean(_ list: [EPGEntry], now: Date? = nil) -> [EPGEntry] {
        EPGStore.clean(list, now: now ?? self.now)
    }
    /// Title and minutes from `now`, as the tests read.
    private func spans(_ list: [EPGEntry]) -> [String] {
        list.map { "\($0.title) \(Int($0.start.timeIntervalSince(now) / 60))-\(Int($0.end.timeIntervalSince(now) / 60))" }
    }
    private func overlaps(_ list: [EPGEntry]) -> Int {
        let sorted = list.sorted { $0.start < $1.start }
        return zip(sorted, sorted.dropFirst()).count(where: { $0.end > $1.start })
    }

    /// The live schedule and the same one ten minutes later with longer matches.
    @Test func twoVersionsOfASchedule() {
        let list = [show("Match", 0, 140), show("Match", 10, 160), show("Goals", 140, 150),
                    show("Derby", 150, 290), show("Derby", 160, 345), show("Goals", 290, 330)]
        #expect(spans(clean(list.shuffled())) == ["Match 0-140", "Goals 140-150", "Derby 150-290", "Goals 290-330"])
    }

    @Test func placeholderAcrossRealShows() {
        let list = [show("LaLiga", 0, 85), show("TBC", 50, 205), show("Herz", 85, 95), show("Highlights", 95, 205)]
        #expect(spans(clean(list)) == ["LaLiga 0-85", "Herz 85-95", "Highlights 95-205"])
    }

    @Test func theSameShowListedTwice() {
        // Starts twenty seconds apart, and two listings with exactly the same start.
        let twice = [show("Border", 0, 21), show("Border", 1 / 3, 21 + 1 / 3), show("Border", 21, 41)]
        #expect(spans(clean(twice)) == ["Border 0-21", "Border 21-41"])
        let sameStart = [show("Pause", 0, 480), show("Pause long", 0, 485), show("News", 480, 500)]
        #expect(spans(clean(sameStart)) == ["Pause 0-480", "News 480-500"])
    }

    /// Up to two minutes of overlap: consecutive shows, the first one ends where the next starts.
    @Test func smallOverlapsKeepBothShows() {
        let kept = clean([show("Film", 0, 76), show("News", 75, 120)])
        #expect(spans(kept) == ["Film 0-75", "News 75-120"])
        #expect(kept.first?.id == "Film 0.0")
        #expect(spans(clean([show("Film", 0, 78), show("News", 75, 120)])) == ["Film 0-78"])
    }

    @Test func listingsWithoutALengthAreDropped() {
        #expect(spans(clean([show("Empty", 10, 10), show("Backwards", 30, 20), show("Show", 0, 30)])) == ["Show 0-30"])
    }

    @Test func aResolvedProgrammeStaysAsItIs() {
        let list = EPGStore.overlapping((0..<12).map { show("Show \($0)", Double($0) * 30, Double($0 + 1) * 30) }, now: now)
        let once = clean(list)
        #expect(overlaps(once) == 0)
        #expect(spans(clean(once)) == spans(once))
    }

    /// The winner of an overlap leaving the kept range (three hours back) does not bring the
    /// loser back: overlaps are resolved on the whole list.
    @Test func theSelectionHoldsWhileTimePasses() {
        let list = [show("Early", 0, 60), show("Loser", 30, 120), show("Late", 60, 120), show("Next", 120, 180)]
        #expect(spans(clean(list)) == ["Early 0-60", "Late 60-120", "Next 120-180"])
        #expect(spans(clean(list, now: at(4 * 60 + 30))) == ["Late 60-120", "Next 120-180"])
    }

    @Test func nextIsNotTheRunningShowsSecondListing() {
        let list = clean([show("Match", -30, 110), show("Match", -20, 130), show("Goals", 110, 120)])
        let (running, next) = EPGStore.nowAndNext(in: list, at: now)
        #expect(running?.title == "Match")
        #expect(next?.title == "Goals")
    }

    /// The debug switch's listings (IPTV_TESTEPGOVERLAP) overlap before the clean-up and not after.
    @Test func debugListingsOverlap() {
        let plain = (-4..<20).map { show("Show \($0)", Double($0) * 25, Double($0 + 1) * 25) }
        let added = EPGStore.overlapping(plain, now: now)
        #expect(added.count == plain.count * 2 + 1)
        #expect(overlaps(added) > plain.count)
        let kept = clean(added)
        #expect(overlaps(kept) == 0)
        #expect(!kept.contains { $0.title.contains("TBC") })
    }

    /// Run over real listings: `FERNSY_EPG_SAMPLE=<directory>` with programme files in the disk
    /// cache's format (`{"entries": [{"t": title, "s": start, "e": end}]}`). Skipped without it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FERNSY_EPG_SAMPLE"] != nil))
    func sampleDirectoryHasNoOverlapsLeft() throws {
        struct Sample: Decodable {
            struct Entry: Decodable { let t: String, s: Date, e: Date }
            let entries: [Entry]
        }
        let dir = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["FERNSY_EPG_SAMPLE"]))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        try #require(!files.isEmpty)
        var listings = 0, affected = 0, dropped = 0, uncovered = 0.0
        for file in files {
            let sample = try JSONDecoder().decode(Sample.self, from: Data(contentsOf: file))
            let list = sample.entries.enumerated().map { EPGEntry(id: "\($0)", title: $1.t, description: "", start: $1.s, end: $1.e) }
            let kept = EPGStore.withoutOverlaps(list)
            #expect(overlaps(kept) == 0, "\(file.lastPathComponent)")
            listings += list.count
            if overlaps(list) > 0 { affected += 1 }
            dropped += list.count(where: { $0.end > $0.start }) - kept.count
            uncovered += covered(list) - covered(kept)
        }
        print("EPG sample: \(files.count) channels, \(listings) listings, \(affected) channels with overlaps, \(dropped) dropped, \(Int((uncovered / 60).rounded())) minutes left uncovered")
    }

    /// Seconds that at least one listing covers.
    private func covered(_ list: [EPGEntry]) -> TimeInterval {
        var total = 0.0, until = Date.distantPast
        for entry in list.sorted(by: { $0.start < $1.start }) where entry.end > until {
            total += entry.end.timeIntervalSince(max(entry.start, until))
            until = entry.end
        }
        return total
    }
}
