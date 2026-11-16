import Foundation
import Testing
@testable import FernsyCore

/// Position against the marks, the card decision and the still-watching count
/// (jellyfin-media-segments, design 4, 6 and 7).
struct SegmentTrackerTests {
    private let marks = SegmentMarks(skips: [.init(kind: .intro, start: 10, end: 25)], credits: .init(start: 95, reachesEnd: true))

    @Test func skipButtonOnlyInsideTheIntro() {
        var tracker = SegmentTracker()
        #expect(tracker.setMarks(marks).isEmpty)
        _ = tracker.update(position: 9)
        #expect(tracker.activeSkip == nil)
        _ = tracker.update(position: 12)
        #expect(tracker.activeSkip?.kind == .intro)
        #expect(tracker.activeSkip?.end == 25)
        _ = tracker.update(position: 25)
        #expect(tracker.activeSkip == nil)
        _ = tracker.update(position: 14)
        _ = tracker.update(position: 1200)
        #expect(tracker.activeSkip == nil, "seeking past the intro hides the button")
    }

    @Test func creditsEnteredAndLeft() {
        var tracker = SegmentTracker()
        _ = tracker.setMarks(marks)
        #expect(tracker.update(position: 94).isEmpty)
        #expect(tracker.update(position: 95) == [.enteredCredits])
        #expect(tracker.update(position: 100).isEmpty)
        #expect(tracker.update(position: 50) == [.leftCredits])
        #expect(!tracker.inCredits)
    }

    /// Segments that arrive while the credits already play show the card at once.
    @Test func lateMarksInsideTheCredits() {
        var tracker = SegmentTracker()
        #expect(tracker.update(position: 100).isEmpty)
        #expect(tracker.setMarks(marks) == [.enteredCredits])
    }

    @Test func automaticSkippingOncePerRange() {
        var tracker = SegmentTracker(skipping: .auto)
        _ = tracker.setMarks(marks)
        #expect(tracker.update(position: 11) == [.autoSkip(kind: .intro, to: 25)])
        #expect(tracker.activeSkip == nil)
        _ = tracker.update(position: 25)
        #expect(tracker.update(position: 12).isEmpty, "seeking back into the intro plays it")
    }

    @Test func neverShowsNoButton() {
        var tracker = SegmentTracker(skipping: .never)
        _ = tracker.setMarks(marks)
        #expect(tracker.update(position: 12).isEmpty)
        #expect(tracker.activeSkip == nil)
    }

    @Test func cardCountsAtTheCredits() {
        let state = NextCardState.decide(hasNext: true, ended: false, inCredits: true, creditsReachEnd: true, dismissed: false,
                                         autoplay: true, stillWatchingDue: false)
        #expect(state == .init(reason: .credits, counts: true, asksStillWatching: false))
    }

    @Test func noCountdownWhenSomethingFollowsTheCredits() {
        let state = NextCardState.decide(hasNext: true, ended: false, inCredits: true, creditsReachEnd: false, dismissed: false,
                                         autoplay: true, stillWatchingDue: false)
        #expect(state == .init(reason: .credits, counts: false, asksStillWatching: false))
        let atTheEnd = NextCardState.decide(hasNext: true, ended: true, inCredits: true, creditsReachEnd: false, dismissed: false,
                                            autoplay: true, stillWatchingDue: false)
        #expect(atTheEnd?.counts == true, "once the file ended the countdown runs")
    }

    @Test func dismissedCardStaysAwayAtTheEnd() {
        #expect(NextCardState.decide(hasNext: true, ended: true, inCredits: true, creditsReachEnd: true, dismissed: true,
                                     autoplay: true, stillWatchingDue: false) == nil)
    }

    @Test func noCardBeforeTheCreditsOrWithoutNext() {
        #expect(NextCardState.decide(hasNext: true, ended: false, inCredits: false, creditsReachEnd: true, dismissed: false,
                                     autoplay: true, stillWatchingDue: false) == nil)
        #expect(NextCardState.decide(hasNext: false, ended: true, inCredits: true, creditsReachEnd: true, dismissed: false,
                                     autoplay: true, stillWatchingDue: false) == nil)
    }

    @Test func autoplayOffShowsTheCardWithoutCountdown() {
        let state = NextCardState.decide(hasNext: true, ended: false, inCredits: true, creditsReachEnd: true, dismissed: false,
                                         autoplay: false, stillWatchingDue: true)
        #expect(state == .init(reason: .credits, counts: false, asksStillWatching: false))
    }

    @Test func stillWatchingReplacesTheCountdown() {
        let state = NextCardState.decide(hasNext: true, ended: false, inCredits: true, creditsReachEnd: true, dismissed: false,
                                         autoplay: true, stillWatchingDue: true)
        #expect(state == .init(reason: .credits, counts: false, asksStillWatching: true))
    }

    @Test func streakAsksAfterThreeAndResetsOnInput() {
        var streak = AutoplayStreak()
        streak.autoStarted()
        streak.autoStarted()
        #expect(!streak.isDue)
        streak.autoStarted()
        #expect(streak.isDue)
        streak.userInput()
        #expect(!streak.isDue)
        streak.autoStarted()
        streak.userInput()
        streak.autoStarted()
        streak.autoStarted()
        #expect(!streak.isDue, "input in between starts the count again")
    }
}
