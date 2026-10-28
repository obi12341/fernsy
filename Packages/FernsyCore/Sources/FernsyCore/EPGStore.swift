import Foundation

/// The programme of one channel. Views observe this per channel, so a channel finishing
/// its download only redraws the rows showing that channel.
@MainActor
public final class ChannelGuide: ObservableObject {
    /// nil until loaded; empty when the server has no programme for the channel.
    @Published public fileprivate(set) var entries: [EPGEntry]?
    /// Set once the full table arrived (the quick now/next answer alone leaves it nil).
    fileprivate var fetchedAt: Date?
}

/// Programme guide cache shared by the channel list and the guide grid. Full tables are
/// also kept on disk (Caches/Fernsy/<account>/epg), so a channel is downloaded again only
/// when its programme runs short or is half a day old, not on every launch.
///
/// Per channel, the quick `get_short_epg` (now + a few hours) is shown first; the full
/// table follows. The table is expensive for the server (it can take many seconds under
/// load), so at most two are requested at a time, the most recently requested first, and
/// a download is cancelled as soon as no view waits for it any more.
@MainActor
public final class EPGStore {
    public init() {}

    /// Days of the provider's archive per channel (catch-up): their past programme is kept that
    /// long instead of three hours. Set by the app when the catalog loads.
    public var archiveDays: [Int: Int] = [:]

    private var guides: [Int: ChannelGuide] = [:]
    private var pending: [Int: (id: UUID, task: Task<Void, Never>)] = [:]
    private var waiters: [Int: Set<UUID>] = [:]
    private var generation = 0
    private var diskChecked: Set<Int> = []
    private var pruned = false
    private let tableSlots = AsyncLimiter(limit: 2)

    public func guide(_ channelId: Int) -> ChannelGuide {
        if let guide = guides[channelId] { return guide }
        let guide = ChannelGuide()
        guides[channelId] = guide
        return guide
    }

    /// Loads the channel's programme; returns when done or when the caller is cancelled.
    public func load(_ channelId: Int, client: XtreamClient?) async {
        let guide = guide(channelId)
        if Self.isFresh(guide) { return }
        guard let client else { return }
        let file = Self.cacheFile(channelId, client: client)
        if !pruned {
            pruned = true
            Task.detached(priority: .background) { Self.prune(file.deletingLastPathComponent()) }
        }
        if guide.fetchedAt == nil, !Self.debugDelayed, diskChecked.insert(channelId).inserted {
            let generation = generation, keepDays = keepDays(channelId)
            if let cached = await Self.read(file, keepDays: keepDays), generation == self.generation, guide.fetchedAt == nil {
                guide.entries = cached.entries
                guide.fetchedAt = cached.fetchedAt
            }
            if Self.isFresh(guide) || Task.isCancelled { return }
        }
        let token = UUID()
        waiters[channelId, default: []].insert(token)
        let task = pending[channelId]?.task ?? {
            let id = UUID(), generation = generation
            let task = Task { await self.fetch(channelId, id: id, into: guide, client: client, generation: generation) }
            pending[channelId] = (id, task)
            return task
        }()
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.leave(channelId, token) }
        }
        leave(channelId, token)
    }

    /// Forgets everything (logout / other account). Guide objects stay, views may hold them.
    public func removeAll() {
        generation += 1
        pending.values.forEach { $0.task.cancel() }
        pending = [:]
        waiters = [:]
        diskChecked = []
        for guide in guides.values {
            guide.entries = nil
            guide.fetchedAt = nil
        }
    }

    private func leave(_ channelId: Int, _ token: UUID) {
        guard waiters[channelId]?.remove(token) != nil, waiters[channelId]?.isEmpty == true else { return }
        waiters[channelId] = nil
        pending[channelId]?.task.cancel()
        pending[channelId] = nil
    }

    private func fetch(_ channelId: Int, id: UUID, into guide: ChannelGuide, client: XtreamClient, generation: Int) async {
        defer { if pending[channelId]?.id == id { pending[channelId] = nil } }

        #if DEBUG
        // IPTV_TESTEPGDELAY=<s>: listings arrive that much later (loading rows in UI tests).
        if let delay = ProcessInfo.processInfo.environment["IPTV_TESTEPGDELAY"].flatMap(Double.init) {
            try? await Task.sleep(for: .seconds(delay))
        }
        #endif
        if guide.entries == nil, let quick = try? await client.shortEPG(channelId, limit: 10),
           !Task.isCancelled, generation == self.generation {
            guide.entries = Self.clean(quick, keepDays: keepDays(channelId))
        }

        guard await tableSlots.acquire() else { return }
        defer { tableSlots.release() }
        guard !Task.isCancelled, let table = try? await client.epgTable(channelId),
              !Task.isCancelled, generation == self.generation else { return }
        let entries = Self.clean(table, keepDays: keepDays(channelId))
        AppLog.detail(.guide, "channel \(channelId): \(table.count) entries, \(entries.count) kept")
        if !entries.isEmpty || guide.entries == nil { guide.entries = entries }
        guide.fetchedAt = Date()
        let file = Self.cacheFile(channelId, client: client), cached = CachedGuide(guide.entries ?? [], fetchedAt: Date())
        Task.detached(priority: .utility) { Self.write(cached, to: file) }
    }

    /// A past day of an archive channel is shown: when the programme does not reach back to
    /// `date` (a cache from before, or a quick answer only), the table is fetched again.
    public func loadPast(_ channelId: Int, client: XtreamClient?, from date: Date) async {
        let guide = guide(channelId)
        await load(channelId, client: client)
        guard keepDays(channelId) > 0, let first = guide.entries?.first?.start, first > date.addingTimeInterval(3600),
              let fetchedAt = guide.fetchedAt, Date().timeIntervalSince(fetchedAt) > 600 else { return }
        guide.fetchedAt = nil
        await load(channelId, client: client)
    }

    /// IPTV_TESTEPGDELAY (debug): the disk cache is skipped too, so rows really load.
    private static var debugDelayed: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["IPTV_TESTEPGDELAY"] != nil
        #else
        false
        #endif
    }

    private func keepDays(_ channelId: Int) -> Int { min(archiveDays[channelId] ?? 0, Archive.maxDays) }

    /// For a visible row: loads the programme, then keeps it fresh until the caller is
    /// cancelled (the row disappears).
    public func keepFresh(_ channelId: Int, client: XtreamClient?) async {
        await load(channelId, client: client)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.recheckInterval))
            if !Task.isCancelled, needsRefresh(channelId) { await load(channelId, client: client) }
        }
    }

    /// Whether the channel's programme should be downloaded again (for rows that stay visible).
    public func needsRefresh(_ channelId: Int) -> Bool {
        !Self.isFresh(guide(channelId))
    }

    /// How often a visible row asks `needsRefresh` (`IPTV_EPGRECHECK=<s>` in debug builds).
    public static var recheckInterval: TimeInterval {
        #if DEBUG
        if let seconds = ProcessInfo.processInfo.environment["IPTV_EPGRECHECK"].flatMap(Double.init) { return seconds }
        #endif
        return 5 * 60
    }

    /// Re-download when half a day old, or when the programme no longer reaches a day
    /// ahead (unless the server simply has no more: then an hour is enough).
    /// `IPTV_EPGSTALE=1` treats every programme as stale in debug builds.
    private static func isFresh(_ guide: ChannelGuide) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_EPGSTALE"] == "1" { return false }
        #endif
        guard let fetchedAt = guide.fetchedAt else { return false }
        let age = Date().timeIntervalSince(fetchedAt)
        if age > 12 * 3600 { return false }
        let reach = guide.entries?.last?.end ?? .distantPast
        return reach > Date().addingTimeInterval(20 * 3600) || age < 3600
    }

    // MARK: Disk cache

    private struct CachedGuide: Codable {
        struct Entry: Codable { let i: String, t: String, d: String, s: Date, e: Date }
        let fetchedAt: Date
        let entries: [Entry]

        init(_ list: [EPGEntry], fetchedAt: Date) {
            self.fetchedAt = fetchedAt
            entries = list.map { Entry(i: $0.id, t: $0.title, d: $0.description, s: $0.start, e: $0.end) }
        }
    }

    nonisolated private static func cacheFile(_ channelId: Int, client: XtreamClient) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fernsy/\(client.credentials.accountKey)/epg/\(channelId).json")
    }

    nonisolated private static func read(_ file: URL, keepDays: Int) async -> (entries: [EPGEntry], fetchedAt: Date)? {
        guard let data = try? Data(contentsOf: file),
              let cached = try? JSONDecoder().decode(CachedGuide.self, from: data) else { return nil }
        let entries = clean(cached.entries.map { EPGEntry(id: $0.i, title: $0.t, description: $0.d, start: $0.s, end: $0.e) }, keepDays: keepDays)
        return (entries, cached.fetchedAt)
    }

    nonisolated private static func write(_ cached: CachedGuide, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cached).write(to: file, options: .atomic)
    }

    /// Channels not looked at for three days.
    nonisolated private static func prune(_ dir: URL) {
        let limit = Date().addingTimeInterval(-3 * 86400)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < limit { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// Sorted, without duplicates, from shortly before now (the guide starts two hours back,
    /// see GuideLayout), or `keepDays` back for a channel with an archive. The table reaches
    /// several days ahead; keeping that is what lets a cached channel stay valid for half a day.
    nonisolated static func clean(_ list: [EPGEntry], keepDays: Int = 0, now: Date = Date()) -> [EPGEntry] {
        let back: TimeInterval = keepDays > 0 ? Double(keepDays) * 86_400 : 3 * 3600
        let from = now.addingTimeInterval(-back), to = now.addingTimeInterval(4 * 86400)
        var seen = Set<Date>()
        return list.sorted { $0.start < $1.start }
            .filter { $0.end > $0.start && $0.end > from && $0.start < to && seen.insert($0.start).inserted }
    }
}

/// At most `limit` holders at a time; waiting callers are served newest first (the row
/// that just scrolled into view matters more than one requested a while ago).
@MainActor
public final class AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiting: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    public init(limit: Int) { self.limit = limit }

    /// false if the caller was cancelled while waiting; it then must not call `release()`.
    public func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if running < limit {
            running += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiting.append((id, $0)) }
        } onCancel: {
            Task { @MainActor in self.drop(id) }
        }
    }

    public func release() {
        if let next = waiting.popLast() {
            next.continuation.resume(returning: true)
        } else {
            running -= 1
        }
    }

    private func drop(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(returning: false)
    }
}
