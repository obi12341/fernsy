import Combine
import FernsyCore
import FernsyPlayer
import Foundation
import SwiftUI

extension AppModel {
    // MARK: Catalog
    //
    // Stale-while-revalidate: the last downloaded catalog is shown straight from disk
    // (live channels first, they are the smallest and most used), then every section
    // is re-downloaded in the background and only re-applied if its bytes changed.

    /// Sections of the catalog that are decoded and applied independently.
    enum CatalogSection: CaseIterable {
        case live, movies, series

        var actions: [CatalogAction] {
            switch self {
            case .live: return [.liveCategories, .liveStreams]
            case .movies: return [.vodCategories, .vodStreams]
            case .series: return [.seriesCategories, .series]
            }
        }
    }

    private enum DecodedSection: Sendable {
        case live([XCategory], [LiveChannel])
        case movies([XCategory], [Movie])
        case series([XCategory], [Series])
    }

    private static let refreshInterval: TimeInterval = 6 * 3600

    var cacheDirectory: URL? {
        guard let credentials else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Fernsy/\(credentials.accountKey)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Shows the cached catalog immediately (if any) and refreshes it in the background.
    /// `forceRefresh` bypasses the "refreshed a moment ago" check (manual refresh).
    func loadCatalog(forceRefresh: Bool) async {
        guard let client, let dir = cacheDirectory else { return }
        loadError = nil

        if channels.isEmpty && movies.isEmpty && series.isEmpty {
            await loadFromCache(dir)
        }
        #if DEBUG
        // A copied account is shown from its cache only: no credentials, no requests.
        if client.credentials.isCopied { return }
        #endif
        if account == nil {
            Task { await refreshAccount(client) }
        }
        startPeriodicRefresh()

        if !forceRefresh, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 300 { return }
        await refresh(client: client, dir: dir)
    }

    private func loadFromCache(_ dir: URL) async {
        let stamp = dir.appendingPathComponent("updated")
        guard let cachedAt = (try? FileManager.default.attributesOfItem(atPath: stamp.path)[.modificationDate]) as? Date else { return }
        lastUpdated = cachedAt

        let started = Date()
        if let live = await Self.decode(.live, from: dir) { apply(live) }
        AppLog.detail(.catalog, "live from cache in \(Int(Date().timeIntervalSince(started) * 1000)) ms (\(channels.count) channels)")

        await withTaskGroup(of: DecodedSection?.self) { group in
            if showsIPTVMovies { group.addTask { await Self.decode(.movies, from: dir) } }
            if showsIPTVSeries { group.addTask { await Self.decode(.series, from: dir) } }
            for await section in group {
                if let section { apply(section) }
            }
        }
        AppLog.detail(.catalog, "full cache in \(Int(Date().timeIntervalSince(started) * 1000)) ms (\(movies.count) movies, \(series.count) series)")
    }

    private func refresh(client: XtreamClient, dir: URL) async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        isLoading = true
        defer {
            refreshInFlight = false
            isLoading = false
        }

        // The package may have changed (stream limit).
        Task { await refreshAccount(client) }
        let started = Date()
        do {
            #if DEBUG
            // IPTV_TESTCATALOGFAIL=1: the refresh fails as if the provider were unreachable.
            if ProcessInfo.processInfo.environment["IPTV_TESTCATALOGFAIL"] != nil { throw URLError(.cannotConnectToHost) }
            #endif
            // Download everything, keep only actions whose payload changed.
            let changed: Set<CatalogAction> = try await withThrowingTaskGroup(of: CatalogAction?.self) { group in
                for action in CatalogSection.allCases.filter(isEnabled).flatMap(\.actions) {
                    group.addTask {
                        let data = try await client.catalog(action)
                        let file = dir.appendingPathComponent(action.rawValue + ".json")
                        if let old = try? Data(contentsOf: file), old == data { return nil }
                        try data.write(to: file, options: .atomic)
                        return action
                    }
                }
                var result = Set<CatalogAction>()
                for try await action in group { if let action { result.insert(action) } }
                return result
            }
            FileManager.default.createFile(atPath: dir.appendingPathComponent("updated").path, contents: Data())
            lastRefresh = Date()
            lastUpdated = lastRefresh

            for section in CatalogSection.allCases where isEnabled(section) && (!changed.isDisjoint(with: section.actions) || isEmpty(section)) {
                if let decoded = await Self.decode(section, from: dir) { apply(decoded) }
            }
            refreshError = nil
            AppLog.info(.catalog, "refresh in \(Int(Date().timeIntervalSince(started) * 1000)) ms, changed: \(changed.map(\.rawValue).sorted())")
        } catch {
            // Without cached data the whole library says so; with it, Live TV shows a notice.
            if channels.isEmpty && movies.isEmpty && series.isEmpty {
                loadError = error.localizedDescription
            } else {
                refreshError = error.localizedDescription
            }
            AppLog.error(.catalog, "refresh failed: \(error.localizedDescription)")
        }
    }

    private func startPeriodicRefresh() {
        guard periodicRefresh == nil else { return }
        periodicRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard let self, !Task.isCancelled else { return }
                await self.loadCatalog(forceRefresh: true)
            }
        }
    }

    private func isEnabled(_ section: CatalogSection) -> Bool {
        switch section {
        case .live: return true
        case .movies: return showsIPTVMovies
        case .series: return showsIPTVSeries
        }
    }

    /// Off: the section is emptied and its cache removed. On: it is downloaded at once, after a
    /// refresh that is still running (which skipped it).
    func catalogSectionSwitched(_ section: CatalogSection, on: Bool) {
        AppLog.info(.catalog, "\(section == .movies ? "films" : "series") switched \(on ? "on" : "off")")
        guard on else {
            apply(section == .movies ? .movies([], []) : .series([], []))
            if let dir = cacheDirectory {
                for action in section.actions { try? FileManager.default.removeItem(at: dir.appendingPathComponent(action.rawValue + ".json")) }
            }
            return
        }
        Task {
            while refreshInFlight { try? await Task.sleep(for: .milliseconds(200)) }
            guard isEnabled(section), let client, let dir = cacheDirectory else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                for action in section.actions {
                    try await client.catalog(action).write(to: dir.appendingPathComponent(action.rawValue + ".json"), options: .atomic)
                }
                if isEnabled(section), let decoded = await Self.decode(section, from: dir) { apply(decoded) }
                AppLog.info(.catalog, "\(section == .movies ? "films" : "series") downloaded")
            } catch {
                refreshError = error.localizedDescription
                AppLog.error(.catalog, "download after switching on failed: \(error.localizedDescription)")
            }
        }
    }

    private func isEmpty(_ section: CatalogSection) -> Bool {
        switch section {
        case .live: return channels.isEmpty
        case .movies: return movies.isEmpty
        case .series: return series.isEmpty
        }
    }

    private nonisolated static func decode(_ section: CatalogSection, from dir: URL) async -> DecodedSection? {
        await Task.detached(priority: .userInitiated) { () -> DecodedSection? in
            func load<T: Decodable>(_ action: CatalogAction, _ type: T.Type) -> T? {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(action.rawValue + ".json")) else { return nil }
                return try? JSONDecoder().decode(T.self, from: data)
            }
            switch section {
            case .live:
                guard let streams = load(.liveStreams, [LiveChannel].self) else { return nil }
                return .live(load(.liveCategories, [XCategory].self) ?? [], streams)
            case .movies:
                guard let streams = load(.vodStreams, [Movie].self) else { return nil }
                return .movies(load(.vodCategories, [XCategory].self) ?? [], streams)
            case .series:
                guard let streams = load(.series, [Series].self) else { return nil }
                return .series(load(.seriesCategories, [XCategory].self) ?? [], streams)
            }
        }.value
    }

    private func apply(_ section: DecodedSection) {
        switch section {
        case .live(let categories, let list):
            channelsByCategory = Dictionary(grouping: list) { $0.categoryId ?? "" }
            liveCategories = categories
            channels = list
            // Archive channels keep their past programme (catch-up design 5).
            epg.archiveDays = Dictionary(list.filter { $0.archiveDays > 0 }.map { ($0.id, $0.archiveDays) }, uniquingKeysWith: { a, _ in a })
            updateVisibleCounts()
        case .movies(let categories, let list):
            moviesByCategory = Dictionary(grouping: list) { $0.categoryId ?? "" }
            movieCategories = categories
            movies = list
        case .series(let categories, let list):
            seriesByCategory = Dictionary(grouping: list) { $0.categoryId ?? "" }
            seriesCategories = categories
            series = list
        }
    }
}
