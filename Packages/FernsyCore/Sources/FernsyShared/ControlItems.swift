import Foundation

/// What the apps and a Fernsy Server exchange through Fernsy Control (headless-recorder design
/// 3). Each item is one of these values, sealed with the control key; one writer per kind.
public enum ControlKind: String, Sendable {
    /// Apps: a recording to make. The id is the order's id, shared with its state.
    case order
    /// Server: what became of an order.
    case state
    /// Server: one item with id `status`.
    case server
    /// Apps: the server was removed (id `removed`, the time as value); a server paired before
    /// that time wipes its secrets, one paired later ignores it.
    case removed
}

public struct ControlOrder: Codable, Equatable, Sendable {
    public var channelId: Int
    public var channelName: String
    public var title: String
    public var showStart: Date
    public var showEnd: Date
    public var padBefore: TimeInterval
    public var padAfter: TimeInterval
    /// The device that scheduled it, as shown in the lists.
    public var createdBy: String
    public var createdAt: Date

    public init(channelId: Int, channelName: String, title: String, showStart: Date, showEnd: Date,
                padBefore: TimeInterval, padAfter: TimeInterval, createdBy: String, createdAt: Date = Date()) {
        self.channelId = channelId
        self.channelName = channelName
        self.title = title
        self.showStart = showStart
        self.showEnd = showEnd
        self.padBefore = padBefore
        self.padAfter = padAfter
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}

public struct ControlOrderState: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case scheduled, recording, uploading, done, failed, refused
    }

    /// Why an order failed or was refused; the apps show their own words for each.
    public enum Reason: String, Codable, Sendable {
        /// The account's stream limit is taken by the server's other recordings.
        case streamLimit = "stream_limit"
        /// The show was over before the server could start (it was off or the order came late).
        case missed
        /// No active Fernsy Cloud subscription at the start or for the upload.
        case noSubscription = "no_subscription"
        /// Not enough Fernsy Cloud storage; the server keeps the file for 7 days.
        case quota
        /// The provider delivered nothing for the whole recording.
        case noStream = "no_stream"
        /// The provider refused the IPTV login.
        case login
        /// The server's disk is full.
        case disk
        case upload
    }

    public var phase: Phase
    public var reason: Reason?
    /// Plaintext bytes recorded so far.
    public var bytes: Int64?
    /// Fernsy Cloud's recording id once uploaded.
    public var cloudId: String?
    public var recordStart: Date?
    public var recordEnd: Date?
    public var updatedAt: Date

    public init(phase: Phase, reason: Reason? = nil, bytes: Int64? = nil, cloudId: String? = nil,
                recordStart: Date? = nil, recordEnd: Date? = nil, updatedAt: Date = Date()) {
        self.phase = phase
        self.reason = reason
        self.bytes = bytes
        self.cloudId = cloudId
        self.recordStart = recordStart
        self.recordEnd = recordEnd
        self.updatedAt = updatedAt
    }

    public var isFinished: Bool { [.done, .failed, .refused].contains(phase) }
}

/// The server's report, written on every poll.
public struct ControlServerStatus: Codable, Equatable, Sendable {
    public var lastContact: Date
    public var version: String
    public var freeBytes: Int64?
    /// Orders recording now (their ids).
    public var running: [String]
    /// The next order to start and when.
    public var nextId: String?
    public var nextStart: Date?
    /// The account's stream limit as the provider reports it.
    public var streamLimit: Int?
    /// Something the user should fix (login refused, disk full), in English for the log.
    public var error: String?

    public init(lastContact: Date, version: String, freeBytes: Int64? = nil, running: [String] = [],
                nextId: String? = nil, nextStart: Date? = nil, streamLimit: Int? = nil, error: String? = nil) {
        self.lastContact = lastContact
        self.version = version
        self.freeBytes = freeBytes
        self.running = running
        self.nextId = nextId
        self.nextStart = nextStart
        self.streamLimit = streamLimit
        self.error = error
    }

    /// The apps show the server as offline after 10 minutes without a report (spec).
    public func isOnline(now: Date = Date()) -> Bool { now.timeIntervalSince(lastContact) < 600 }
}

/// Dates as seconds since 2001 (Foundation's default): exact, unlike ISO 8601 without fractions.
public extension ControlKey {
    func seal<Value: Encodable>(_ value: Value, kind: ControlKind, id: String) throws -> Data {
        try seal(try JSONEncoder().encode(value), kind: kind.rawValue, id: id)
    }

    func open<Value: Decodable>(_ item: ControlClient.Item, as type: Value.Type) throws -> Value {
        guard let data = item.data else { throw ControlClient.Failure.notFound }
        return try JSONDecoder().decode(type, from: try open(data, kind: item.kind, id: item.id))
    }
}
