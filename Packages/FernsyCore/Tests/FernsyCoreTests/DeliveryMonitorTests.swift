import Foundation
import Testing
@testable import FernsyCore

/// The slow-delivery rule (playback spec, "Slow live delivery"), fed with a clock: the watchdog
/// samples every 0.5 s; `content(t)` is the content time received by second t.
struct DeliveryMonitorTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    struct Event: Equatable {
        let at: Double
        let decision: DeliveryMonitor.Decision
    }

    /// Runs the rule from `from` to `to` seconds. A replaced connection is answered again at once
    /// (the reconnect itself takes no time here).
    static func run(_ monitor: inout DeliveryMonitor, from: Double = 0, to: Double, answeredAt: Double = 0,
                    content: (Double) -> Double) -> [Event] {
        var events: [Event] = []
        var answered = answeredAt
        var t = from
        while t <= to {
            let now = start.addingTimeInterval(t)
            let reading = monitor.sample(at: now, content: content(t))
            let decision = monitor.decide(at: now, reading: reading, connectionAge: t - answered)
            if decision != .keep {
                events.append(Event(at: t, decision: decision))
                if case .replace = decision {
                    monitor.connectionAnswered()
                    answered = t
                }
            }
            _ = monitor.relax(at: now)
            t += 0.5
        }
        return events
    }

    @Test func demoServerDeliveryIsKept() {
        // Measured on the demo server: 2-4 s bursts, 11-14 s per 15 s window.
        var monitor = DeliveryMonitor()
        let events = Self.run(&monitor, to: 300) { t in (t / 3).rounded(.down) * 3 }
        #expect(events.isEmpty)
        #expect((monitor.lowestWindow ?? 0) >= 11)
    }

    @Test func sixSecondBurstsAreKept() {
        var monitor = DeliveryMonitor()
        let events = Self.run(&monitor, to: 300) { t in (t / 6).rounded(.down) * 6 }
        #expect(events.isEmpty)
    }

    @Test func aFifthOfRealTimeIsReplacedWithin20Seconds() throws {
        var monitor = DeliveryMonitor()
        let events = Self.run(&monitor, to: 60) { t in t < 30 ? t : 30 + (t - 30) * 0.2 }
        let first = try #require(events.first)
        guard case .replace(let delivered, let window) = first.decision else {
            Issue.record("expected a replacement, got \(first.decision)")
            return
        }
        #expect(window == 15)
        #expect(delivered < 9)
        #expect(first.at > 30 && first.at <= 50)
    }

    @Test func aYoungConnectionIsNotJudgedBeforeItsWindow() {
        // Slow from the start: the 15 s window needs 20 s of connection.
        var monitor = DeliveryMonitor()
        let events = Self.run(&monitor, to: 19.5) { t in t * 0.2 }
        #expect(events.isEmpty)
    }

    @Test func switchingThatDoesNotHelpLengthensTheWindow() {
        // Every connection delivers a fifth of real time (the user's own line is slow).
        var monitor = DeliveryMonitor()
        let events = Self.run(&monitor, to: 240) { t in t * 0.2 }
        let kinds = events.map { event -> String in
            switch event.decision {
            case .keep: "keep"
            case .replace(_, let window): "replace \(Int(window))"
            case .lengthen(_, let window): "lengthen \(Int(window))"
            }
        }
        #expect(Array(kinds.prefix(4)) == ["replace 15", "lengthen 30", "lengthen 60", "replace 60"])
        // About one switch a minute instead of every 20 s.
        let replaces = events.filter { if case .replace = $0.decision { true } else { false } }
        #expect(replaces.count <= 4)
        #expect(monitor.level == 2)
    }

    @Test func fiveQuietMinutesReturnTo15Seconds() {
        var monitor = DeliveryMonitor()
        _ = Self.run(&monitor, to: 120) { t in t * 0.2 }
        #expect(monitor.level > 0)
        let base = 120 * 0.2
        monitor.connectionAnswered()
        _ = Self.run(&monitor, from: 120.5, to: 500, answeredAt: 120) { t in base + (t - 120) }
        #expect(monitor.level == 0)
        #expect(monitor.window == 15)
    }

    @Test func slowNowForTheCard() {
        // Real time until 30 s, then nothing: the card rule (under 5 s in 12 s) fires before the
        // connection could be judged on a full 15 s window of a young connection.
        var monitor = DeliveryMonitor()
        var reading = DeliveryMonitor.Reading.none
        for step in 0...80 {
            let t = Double(step) * 0.5
            reading = monitor.sample(at: Self.start.addingTimeInterval(t), content: min(t, 30))
        }
        #expect(reading.slow)
    }

    @Test func realTimeAfterASwitch() {
        var fast = DeliveryMonitor()
        var slow = DeliveryMonitor()
        for step in 0...12 {
            let t = Double(step) * 0.5
            _ = fast.sample(at: Self.start.addingTimeInterval(t), content: t)
            _ = slow.sample(at: Self.start.addingTimeInterval(t), content: t * 0.3)
        }
        #expect(fast.deliversInRealTime)
        #expect(!slow.deliversInRealTime)
    }

    @Test func recentSlownessIsRemembered() {
        var monitor = DeliveryMonitor()
        _ = Self.run(&monitor, to: 40) { t in t < 20 ? t : 20 }
        #expect(monitor.wasSlow(within: 60, at: Self.start.addingTimeInterval(41)))
        #expect(!monitor.wasSlow(within: 60, at: Self.start.addingTimeInterval(200)))
    }

    @Test func figuresPerConnection() {
        var monitor = DeliveryMonitor()
        _ = Self.run(&monitor, to: 60) { t in t }
        monitor.notePause(3.2)
        monitor.notePause(1.0)
        #expect(monitor.longestPause == 3.2)
        #expect(abs((monitor.lowestWindow ?? 0) - 15) < 1)
        monitor.connectionAnswered()
        #expect(monitor.lowestWindow == nil)
        #expect(monitor.longestPause == 0)
    }
}
