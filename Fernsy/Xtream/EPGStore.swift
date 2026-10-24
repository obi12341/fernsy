import Foundation

/// The programme of one channel. Views observe this per channel, so a channel finishing
/// its download only redraws the rows showing that channel.
@MainActor
final class ChannelGuide: ObservableObject {
    /// nil until loaded; empty when the server has no programme for the channel.
    @Published fileprivate(set) var entries: [EPGEntry]?
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
final class EPGStore {
    private var guides: [Int: ChannelGuide] = [:]
    private var pending: [Int: (id: UUID, task: Task<Void, Never>)] = [:]
    private var waiters: [Int: Set<UUID>] = [:]
    private var generation = 0
    private var diskChecked: Set<Int> = []
    private var pruned = false
    private let tableSlots = AsyncLimiter(limit: 2)

    func guide(_ channelId: Int) -> ChannelGuide {
        if let guide = guides[channelId] { return guide }
        let guide = ChannelGuide()
        guides[channelId] = guide
        return guide
    }

    /// Loads the channel's programme; returns when done or when the caller is cancelled.
    func load(_ channelId: Int, client: XtreamClient?) async {
        let guide = guide(channelId)
        if Self.isFresh(guide) { return }
        guard let client else { return }
        let file = Self.cacheFile(channelId, client: client)
        if !pruned {
            pruned = true
            Task.detached(priority: .background) { Self.prune(file.deletingLastPathComponent()) }
        }
        if guide.fetchedAt == nil, diskChecked.insert(channelId).inserted {
            let generation = generation
            if let cached = await Self.read(file), generation == self.generation, guide.fetchedAt == nil {
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
    func removeAll() {
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

        if guide.entries == nil, let quick = try? await client.shortEPG(channelId, limit: 10),
           !Task.isCancelled, generation == self.generation {
            guide.entries = Self.clean(quick)
        }

        guard await tableSlots.acquire() else { return }
        defer { tableSlots.release() }
        guard !Task.isCancelled, let table = try? await client.epgTable(channelId),
              !Task.isCancelled, generation == self.generation else { return }
        let entries = Self.clean(table)
        AppLog.detail(.guide, "channel \(channelId): \(table.count) entries, \(entries.count) kept")
        if !entries.isEmpty || guide.entries == nil { guide.entries = entries }
        guide.fetchedAt = Date()
        let file = Self.cacheFile(channelId, client: client), cached = CachedGuide(guide.entries ?? [], fetchedAt: Date())
        Task.detached(priority: .utility) { Self.write(cached, to: file) }
    }

    /// Re-download when half a day old, or when the programme no longer reaches a day
    /// ahead (unless the server simply has no more: then an hour is enough).
    private static func isFresh(_ guide: ChannelGuide) -> Bool {
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

    nonisolated private static func read(_ file: URL) async -> (entries: [EPGEntry], fetchedAt: Date)? {
        guard let data = try? Data(contentsOf: file),
              let cached = try? JSONDecoder().decode(CachedGuide.self, from: data) else { return nil }
        let entries = clean(cached.entries.map { EPGEntry(id: $0.i, title: $0.t, description: $0.d, start: $0.s, end: $0.e) })
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
    /// see GuideLayout). The table reaches several days ahead; keeping that is what lets a
    /// cached channel stay valid for half a day.
    nonisolated private static func clean(_ list: [EPGEntry]) -> [EPGEntry] {
        let from = Date().addingTimeInterval(-3 * 3600), to = Date().addingTimeInterval(4 * 86400)
        var seen = Set<Date>()
        return list.sorted { $0.start < $1.start }
            .filter { $0.end > $0.start && $0.end > from && $0.start < to && seen.insert($0.start).inserted }
    }
}

/// At most `limit` holders at a time; waiting callers are served newest first (the row
/// that just scrolled into view matters more than one requested a while ago).
@MainActor
final class AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiting: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    init(limit: Int) { self.limit = limit }

    /// false if the caller was cancelled while waiting; it then must not call `release()`.
    func acquire() async -> Bool {
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

    func release() {
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
