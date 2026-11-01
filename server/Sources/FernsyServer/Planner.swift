import FernsyShared
import Foundation

/// What the server does with its orders at a moment (headless-recorder spec "Orders from the
/// apps"): a pure function of orders, states and time, so it is tested without network or clock.
enum Planner {
    enum Action: Equatable {
        /// A new order fits: it becomes scheduled.
        case schedule(String)
        case refuse(String, ControlOrderState.Reason)
        /// The show was over before it could start.
        case miss(String)
        /// Start recording this order now, until `until`.
        case start(String, until: Date)
        /// Stop a running recording (its window ended or the limit moved it).
        case stop(String)
    }

    struct Entry {
        var order: ControlOrder
        var state: ControlOrderState?
        /// When the server started recording it (nil when not running).
        var runningSince: Date?
    }

    static func item(_ id: String, _ entry: Entry) -> RecordingPlan.Item {
        RecordingPlan.Item(id: uuid(id), channelId: entry.order.channelId, start: entry.order.showStart, end: entry.order.showEnd,
                           padBefore: entry.order.padBefore, padAfter: entry.order.padAfter, runningSince: entry.runningSince)
    }

    /// Order ids are UUID strings from the apps; anything else maps to a stable UUID of its hash.
    static func uuid(_ id: String) -> UUID {
        if let uuid = UUID(uuidString: id) { return uuid }
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in id.utf8.enumerated() { bytes[i % 16] = bytes[i % 16] &* 31 &+ b }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func actions(_ entries: [String: Entry], limit: Int, now: Date) -> [Action] {
        var actions: [Action] = []
        var accepted = entries.filter { $0.value.state.map { !$0.isFinished } ?? false }
        // New orders, oldest first: admitted against what is already accepted.
        for (id, entry) in entries.filter({ $0.value.state == nil }).sorted(by: { $0.value.order.createdAt < $1.value.order.createdAt }) {
            if entry.order.showEnd <= now {
                actions.append(.miss(id))
                continue
            }
            let blockers = RecordingPlan.blockers(for: item(id, entry), among: accepted.map { item($0.key, $0.value) }, limit: limit, now: now)
            if blockers.isEmpty {
                actions.append(.schedule(id))
                accepted[id] = Entry(order: entry.order, state: ControlOrderState(phase: .scheduled))
            } else {
                actions.append(.refuse(id, .streamLimit))
            }
        }
        let windows = RecordingPlan.windows(for: accepted.map { item($0.key, $0.value) }, limit: limit, now: now)
        // Stops before starts: a recording that begins where another ends takes over its
        // connection (recordings spec "Handover between back-to-back recordings").
        var starts: [Action] = []
        for (id, entry) in accepted.sorted(by: { $0.key < $1.key }) {
            guard let window = windows[uuid(id)] else { continue }
            let phase = entry.state?.phase ?? .scheduled
            if entry.runningSince != nil {
                if window.end <= now { actions.append(.stop(id)) }
            } else if phase == .scheduled {
                if window.end <= now { actions.append(.miss(id)) }
                else if window.start <= now { starts.append(.start(id, until: window.end)) }
            }
        }
        return actions + starts
    }

    /// The next moment something starts, for the status.
    static func next(_ entries: [String: Entry], limit: Int, now: Date) -> (id: String, start: Date)? {
        let waiting = entries.filter { $0.value.state?.phase == .scheduled && $0.value.runningSince == nil }
        let windows = RecordingPlan.windows(for: entries.filter { $0.value.state.map { !$0.isFinished } ?? false }.map { item($0.key, $0.value) },
                                            limit: limit, now: now)
        return waiting.compactMap { id, _ in windows[uuid(id)].map { (id, $0.start) } }.min { $0.1 < $1.1 }
    }
}
