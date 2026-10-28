import Foundation
import Testing
@testable import FernsyCore

/// The guide's free stretches (tvos-guide-empty-channels 2.2).
struct GuideGapsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var window: ClosedRange<Date> { start...start.addingTimeInterval(3 * 3600) }

    private func minutes(_ m: Double) -> Date { start.addingTimeInterval(m * 60) }
    private func show(_ from: Double, _ to: Double) -> EPGEntry {
        EPGEntry(id: "\(from)", title: "Show", description: "", start: minutes(from), end: minutes(to))
    }

    @Test func noListingsIsOneGapOverTheWindow() {
        #expect(GuideGaps.free(shows: [], window: window) == [window])
    }

    @Test func listingsEndingEarly() {
        let gaps = GuideGaps.free(shows: [show(-30, 30), show(30, 60)], window: window)
        #expect(gaps == [minutes(60)...minutes(180)])
    }

    @Test func gapBetweenShowsAndBeforeTheFirst() {
        let gaps = GuideGaps.free(shows: [show(70, 100), show(20, 40), show(100, 200)], window: window)
        #expect(gaps == [minutes(0)...minutes(20), minutes(40)...minutes(70)])
    }

    @Test func shortGapsAreLeftOut() {
        let gaps = GuideGaps.free(shows: [show(0, 50), show(60, 170)], window: window)
        #expect(gaps.isEmpty)
    }
}
