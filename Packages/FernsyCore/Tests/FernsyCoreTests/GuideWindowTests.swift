import Foundation
import Testing
@testable import FernsyCore

/// The Apple TV guide's window as time passes (a guide left open overnight showed last night).
struct GuideWindowTests {
    private let span: TimeInterval = 3 * 3600
    /// 00:43 on a whole hour boundary in UTC terms: half hours are timezone-free.
    private let opened = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 3600) + 43 * 60)

    private func later(_ minutes: Double) -> Date { opened.addingTimeInterval(minutes * 60) }

    @Test func startsHalfAnHourBeforeTheCurrentHalfHour() {
        #expect(GuideWindow.start(at: opened) == later(-43))
    }

    @Test func aPlacedWindowStaysWhileNowIsWellInside() {
        let placed = GuideWindow.start(at: opened)
        #expect(GuideWindow.update(current: placed, placed: placed, span: span, now: later(60)) == nil)
    }

    @Test func aPlacedWindowMovesOnNearItsEnd() {
        let placed = GuideWindow.start(at: opened)
        let now = later(110)
        #expect(GuideWindow.update(current: placed, placed: placed, span: span, now: now) == GuideWindow.start(at: now))
    }

    @Test func aPagedWindowStays() {
        let placed = GuideWindow.start(at: opened)
        let paged = placed.addingTimeInterval(-6 * 3600)
        #expect(GuideWindow.update(current: paged, placed: placed, span: span, now: later(200)) == nil)
    }

    @Test func overnightTheGuideOpensAtNowAgain() {
        let placed = GuideWindow.start(at: opened)
        let now = later(18 * 60 + 44)
        #expect(GuideWindow.update(current: placed, placed: placed, span: span, hiddenFor: 18 * 3600, now: now) == GuideWindow.start(at: now))
        let paged = placed.addingTimeInterval(-6 * 3600)
        #expect(GuideWindow.update(current: paged, placed: placed, span: span, hiddenFor: 18 * 3600, now: now) == GuideWindow.start(at: now))
    }

    @Test func aShortAbsenceKeepsAPagedWindow() {
        let placed = GuideWindow.start(at: opened)
        let paged = placed.addingTimeInterval(-6 * 3600)
        #expect(GuideWindow.update(current: paged, placed: placed, span: span, hiddenFor: 10 * 60, now: later(20)) == nil)
    }
}
