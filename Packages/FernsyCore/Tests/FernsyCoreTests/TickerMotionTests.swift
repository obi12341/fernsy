import Foundation
import Testing
@testable import FernsyCore

/// The sliding text's offset over time (tvos-guide-name-ticker 1.1). A text 80 points too long
/// takes 2 s per pass at 40 points per second, with 1 s of rest at both ends: one loop is 6 s.
struct TickerMotionTests {
    private func offset(_ elapsed: TimeInterval, distance: Double = 80) -> Double {
        TickerMotion.offset(after: elapsed, distance: distance)
    }

    @Test func restsAtTheBeginning() {
        #expect(offset(0) == 0)
        #expect(offset(0.5) == 0)
        #expect(offset(0.99) == 0)
    }

    @Test func slidesToTheEnd() {
        #expect(abs(offset(1.5) - 20) < 0.001)
        #expect(abs(offset(2) - 40) < 0.001)
        #expect(abs(offset(2.9) - 76) < 0.001)
    }

    @Test func restsAtTheEnd() {
        #expect(offset(3) == 80)
        #expect(offset(3.5) == 80)
        #expect(offset(3.99) == 80)
    }

    @Test func slidesBack() {
        #expect(abs(offset(4.5) - 60) < 0.001)
        #expect(abs(offset(5) - 40) < 0.001)
        #expect(abs(offset(5.9) - 4) < 0.001)
    }

    @Test func theNextLoopIsTheSame() {
        for time in [0.0, 0.5, 1.5, 2, 3.5, 5, 5.9] {
            #expect(abs(offset(time + 6) - offset(time)) < 0.001, "at \(time) s")
            #expect(abs(offset(time + 60) - offset(time)) < 0.001, "at \(time) s, ten loops later")
        }
    }

    @Test func neverLeavesItsRange() {
        for step in 0..<600 {
            let value = offset(Double(step) * 0.05)
            #expect(value >= 0 && value <= 80, "at \(Double(step) * 0.05) s: \(value)")
        }
    }

    @Test func aTextThatFitsDoesNotMove() {
        for time in [0.0, 1.5, 3, 10] {
            #expect(offset(time, distance: 0) == 0)
            #expect(offset(time, distance: -12) == 0)
        }
    }

    @Test func aLongerTextTakesLongerAtTheSameSpeed() {
        // 200 points: 5 s per pass. After 1 s of rest and 2 s of sliding both have moved 80 points.
        #expect(abs(offset(3, distance: 200) - 80) < 0.001)
        #expect(abs(offset(6, distance: 200) - 200) < 0.001)
    }
}
