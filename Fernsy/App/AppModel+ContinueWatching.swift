import AppKit
import FernsyCore
import Foundation

/// Continue Watching from every device on the Mac (continue-watching-fresh), as in the Apple TV
/// and iPhone model: episode lists kept on the Mac, the series of started episodes, and asking
/// iCloud and Jellyfin again when the app is activated.
extension AppModel {
    /// Episode lists kept for the signed-in account.
    var seriesInfoStore: SeriesInfoStore? {
        cacheDirectory.map { SeriesInfoStore(folder: $0.appendingPathComponent("series-info", isDirectory: true)) }
    }

    /// A series' episode list is here: Start can name its episodes, and positions saved without
    /// their series (older versions) get it.
    func keep(_ info: SeriesInfo, for seriesId: Int) {
        seriesInfos[seriesId] = info
        if resume.adoptSeries(seriesId, episodes: info.seasons.values.flatMap { $0 }.map(\.id)) > 0 { resumeRevision += 1 }
    }

    /// The series page: from the provider (kept on the Mac), the kept list when the provider does
    /// not answer; nil without an account.
    func seriesDetails(_ seriesId: Int) async throws -> SeriesInfo? {
        guard let client else { return nil }
        do {
            let data = try await client.seriesInfoData(seriesId)
            let info = try seriesInfoStore?.save(data, for: seriesId) ?? JSONDecoder().decode(SeriesInfo.self, from: data)
            freshSeriesInfo.insert(seriesId)
            keep(info, for: seriesId)
            AppLog.detail(.catalog, "episodes of series \(seriesId) loaded and kept")
            return info
        } catch {
            guard let kept = seriesInfoStore?.load(seriesId) else { throw error }
            keep(kept, for: seriesId)
            return kept
        }
    }

    /// The episode lists Start needs for the started episodes: kept ones first, then the provider,
    /// one series after the other (design 4). A failed request is tried at the next trigger.
    func loadStartedSeries() async {
        guard showsIPTVSeries, !series.isEmpty, !loadingStartedSeries else { return }
        let missing = StartedEpisodes.missingSeries(resume: resume, known: Set(seriesInfos.keys), catalog: Set(series.map(\.id)))
        guard !missing.isEmpty else { return }
        loadingStartedSeries = true
        defer { loadingStartedSeries = false }
        var fromProvider: [Int] = []
        for id in missing {
            if let kept = seriesInfoStore?.load(id) {
                keep(kept, for: id)
                AppLog.info(.app, "Start: episodes of series \(id) from the device")
            } else {
                fromProvider.append(id)
            }
        }
        if fromProvider.count < missing.count { resumeRevision += 1 }
        for id in fromProvider {
            _ = try? await seriesDetails(id)
            guard freshSeriesInfo.contains(id) else { continue }
            AppLog.info(.app, "Start: episodes of series \(id) from the provider")
            resumeRevision += 1
        }
    }

    /// Activated: what the other devices did meanwhile (design 1).
    func refreshFromOtherDevices() {
        AppLog.detail(.app, "back in the front: asking iCloud and Jellyfin again")
        sync.refresh()
        if jellyfin.session != nil, jellyfinHomeThrottle.allow() {
            AppLog.detail(.jellyfin, "Start's rows loaded again")
            Task { await jellyfin.refreshHome() }
        }
        Task { await loadStartedSeries() }
    }

    func startActivationWatch() {
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFromOtherDevices() }
        }
    }
}
