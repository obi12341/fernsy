import Foundation

/// Receives one live channel from the network into its timeshift buffer, for the player and
/// for recordings at the same time (one connection).
///
/// Wraps a headless PlaybackSession (`.tuner`) and restarts it when the stream breaks for
/// good; the TimeshiftWriter keeps the buffer's timeline continuous across restarts.
@MainActor
final class LiveTuner: ObservableObject {
    enum State: Equatable {
        case connecting
        case running
        case reconnecting
        case failed(String)
        /// The streams cannot be remuxed; the player falls back to direct playback.
        case unsupported
        case stopped
    }

    nonisolated let channelId: Int
    nonisolated let url: URL
    nonisolated let buffer: TimeshiftBuffer
    @Published private(set) var state: State = .connecting

    /// Recordings keep a tuner trying for as long as they run; the player alone gives up
    /// after a few attempts like before.
    var keepTrying = false
    /// The provider reported the channel offline (true) or it delivers again (false).
    var onOffline: ((Bool) -> Void)?

    private let writer: TimeshiftWriter
    nonisolated private let holder = SessionHolder()
    private let control = DispatchQueue(label: "tuner.control", qos: .userInitiated)
    private var generation = 0
    private var attempts = 0
    private var openedAt: Date?

    init(channelId: Int, url: URL, keepSeconds: Double) {
        self.channelId = channelId
        self.url = url
        buffer = TimeshiftBuffer(channelId: channelId, keepSeconds: keepSeconds)
        writer = TimeshiftWriter(buffer: buffer)
        let holder = holder
        buffer.setStatsProvider { holder.session?.networkStats ?? (HTTPByteSource.NetStats(), 0) }
        connect()
    }

    var isActive: Bool {
        switch state {
        case .connecting, .running, .reconnecting: return true
        default: return false
        }
    }

    func stop() {
        guard state != .stopped else { return }
        generation += 1
        state = .stopped
        let holder = holder, writer = writer
        control.async {
            holder.session?.stop()
            holder.session = nil
            writer.close()
        }
    }

    /// Seconds the player still has ahead of its position (stall detection on the connection).
    nonisolated func reportPlaybackAhead(_ seconds: Double) {
        holder.session?.reportPlaybackAhead(seconds)
    }

    private func connect() {
        generation += 1
        let gen = generation
        let url = url, writer = writer, holder = holder
        control.async { [weak self] in
            // Single-connection accounts: the old connection must be closed first.
            holder.session?.stop()
            let session = PlaybackSession(tunerURL: url, output: writer) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event, generation: gen) }
            }
            holder.session = session
            session.start()
        }
    }

    private func handle(_ event: PlaybackSession.Event, generation gen: Int) {
        guard gen == generation else { return }
        switch event {
        case .opened:
            state = .running
            openedAt = Date()
            onOffline?(false)
        case .failed(let message, let retry):
            if retry || keepTrying {
                AppLog.warning(.tuner, "channel \(channelId), reconnecting: \(message)")
            } else {
                AppLog.error(.tuner, "channel \(channelId) failed: \(message)")
            }
            // Not retryable and still muxable: the provider's offline placeholder.
            if !retry && !writer.isFailed { onOffline?(true) }
            if writer.isFailed {
                state = .unsupported
                stopSession()
            } else if retry {
                restart(reason: message)
            } else if keepTrying {
                // Offline at the provider: a recording waits for the channel until its window
                // ends, asking calmly (the player alone gives up below).
                restart(reason: message, after: 30)
            } else {
                state = .failed(message)
                stopSession()
            }
        default:
            break
        }
    }

    private func restart(reason: String, after fixedDelay: TimeInterval? = nil) {
        if let openedAt, Date().timeIntervalSince(openedAt) > 20 { attempts = 0 }
        openedAt = nil
        guard attempts < 8 || keepTrying else {
            state = .failed(reason)
            stopSession()
            return
        }
        attempts += 1
        state = .reconnecting
        let gen = generation
        let delay = fixedDelay ?? min(keepTrying ? 10 : 5, 0.5 * Double(attempts))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.connect()
        }
    }

    private func stopSession() {
        generation += 1
        let holder = holder, writer = writer
        control.async {
            holder.session?.stop()
            holder.session = nil
            writer.close()
        }
    }
}

/// The tuner's current session, readable from the buffer's stats callback on any thread.
private final class SessionHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PlaybackSession?

    var session: PlaybackSession? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

/// The live connections Fernsy holds: at most as many as the account allows. A tuner is
/// shared by everyone who needs that channel (player, recordings) and closed when the last
/// one lets go.
@MainActor
final class TunerPool: ObservableObject {
    enum Owner: Hashable {
        case player
        case recording(UUID)
    }

    @Published private(set) var owners: [Int: Set<Owner>] = [:]
    private var tuners: [Int: LiveTuner] = [:]
    /// Simultaneous streams the account allows.
    var limit = 1
    /// A channel was reported offline by the provider, or delivers again.
    var onOffline: ((Int, Bool) -> Void)?
    var keepSeconds: Double = 3600 {
        didSet { for tuner in tuners.values { tuner.buffer.keepSeconds = keepSeconds } }
    }

    init() {
        TimeshiftBuffer.removeLeftovers()
    }

    func tuner(_ channelId: Int) -> LiveTuner? { tuners[channelId] }

    func acquire(_ channelId: Int, url: URL, owner: Owner) -> LiveTuner {
        if let tuner = tuners[channelId], tuner.isActive || tuner.state == .unsupported {
            owners[channelId, default: []].insert(owner)
            updateKeepTrying(channelId)
            return tuner
        }
        tuners[channelId]?.stop()
        let tuner = LiveTuner(channelId: channelId, url: url, keepSeconds: keepSeconds)
        tuner.onOffline = { [weak self] offline in self?.onOffline?(channelId, offline) }
        tuners[channelId] = tuner
        owners[channelId, default: []].insert(owner)
        updateKeepTrying(channelId)
        return tuner
    }

    func release(_ channelId: Int, owner: Owner) {
        owners[channelId]?.remove(owner)
        if owners[channelId]?.isEmpty ?? true {
            owners[channelId] = nil
            tuners[channelId]?.stop()
            tuners[channelId] = nil
        } else {
            updateKeepTrying(channelId)
        }
    }

    /// Channels (with their owners) that would have to give way before `owner` can tune
    /// `channelId`. Empty when there is a free connection or the channel is already tuned.
    func blockers(for channelId: Int, as owner: Owner) -> [(channelId: Int, owners: Set<Owner>)] {
        if tuners[channelId] != nil { return [] }
        let others = owners.filter { $0.key != channelId && !$0.value.subtracting([owner]).isEmpty }
        guard others.count >= limit else { return [] }
        return others.map { ($0.key, $0.value) }.sorted { $0.channelId < $1.channelId }
    }

    func stopAll() {
        for tuner in tuners.values { tuner.stop() }
        tuners = [:]
        owners = [:]
    }

    private func updateKeepTrying(_ channelId: Int) {
        tuners[channelId]?.keepTrying = owners[channelId]?.contains { if case .recording = $0 { true } else { false } } ?? false
    }
}
