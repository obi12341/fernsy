import FernsyShared
import Foundation
import Testing
@testable import FernsyServer

struct PlannerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func order(_ channel: Int, from start: TimeInterval, to end: TimeInterval, pad: TimeInterval = 0, created: TimeInterval = 0) -> ControlOrder {
        ControlOrder(channelId: channel, channelName: "C\(channel)", title: "Show", showStart: now + start, showEnd: now + end,
                     padBefore: pad, padAfter: pad, createdBy: "Test", createdAt: now + created)
    }

    @Test func newOrdersAreScheduledOrRefusedOverTheLimit() {
        let entries: [String: Planner.Entry] = [
            "a": .init(order: order(1, from: 3600, to: 7200, created: 0)),
            "b": .init(order: order(2, from: 3600, to: 7200, created: 1)),
            "c": .init(order: order(1, from: 5400, to: 9000, created: 2)),   // same channel as a: shares its stream
            "d": .init(order: order(3, from: -7200, to: -3600, created: 3)),
        ]
        let actions = Planner.actions(entries, limit: 1, now: now)
        #expect(actions.contains(.schedule("a")))
        #expect(actions.contains(.refuse("b", .streamLimit)))
        #expect(actions.contains(.schedule("c")))
        #expect(actions.contains(.miss("d")))
    }

    @Test func recordingsStartWithTheirPaddingAndStopAfterIt() {
        let scheduled = ControlOrderState(phase: .scheduled)
        var entries: [String: Planner.Entry] = ["a": .init(order: order(1, from: 60, to: 3600, pad: 120), state: scheduled)]
        #expect(Planner.actions(entries, limit: 1, now: now) == [.start("a", until: now + 3720)])
        #expect(Planner.next(entries, limit: 1, now: now)?.start == now - 60)
        entries["a"]?.runningSince = now - 60
        entries["a"]?.state = ControlOrderState(phase: .recording)
        #expect(Planner.actions(entries, limit: 1, now: now + 3600).isEmpty)
        #expect(Planner.actions(entries, limit: 1, now: now + 3720) == [.stop("a")])
    }

    @Test func aScheduledOrderWhoseWindowPassedIsMissed() {
        let entries: [String: Planner.Entry] = ["a": .init(order: order(1, from: -3600, to: -60), state: ControlOrderState(phase: .scheduled))]
        #expect(Planner.actions(entries, limit: 1, now: now) == [.miss("a")])
    }

    @Test func finishedOrdersAreLeftAlone() {
        let entries: [String: Planner.Entry] = ["a": .init(order: order(1, from: -60, to: 3600), state: ControlOrderState(phase: .done))]
        #expect(Planner.actions(entries, limit: 1, now: now).isEmpty)
    }

    @Test func backToBackRecordingsHandOverTheConnection() {
        var entries: [String: Planner.Entry] = [
            "z": .init(order: order(1, from: -3600, to: 0), state: ControlOrderState(phase: .recording), runningSince: now - 3600),
            "a": .init(order: order(2, from: 0, to: 3600), state: ControlOrderState(phase: .scheduled)),
        ]
        #expect(Planner.actions(entries, limit: 1, now: now) == [.stop("z"), .start("a", until: now + 3600)])
        entries["z"] = nil
        #expect(Planner.actions(entries, limit: 1, now: now) == [.start("a", until: now + 3600)])
    }
}
