import Foundation

/// Episode lists of series kept on the device, per provider account, so Start can name a
/// started episode right after a launch and without a connection (continue-watching-fresh
/// design 3). It keeps the provider's answer as it came (`<series id>.json`) and decodes it with
/// `SeriesInfo`'s decoder, which absorbs the providers' irregular JSON.
public struct SeriesInfoStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    private func file(_ seriesId: Int) -> URL { folder.appendingPathComponent("\(seriesId).json") }

    /// Keeps the answer; one that does not decode is not kept.
    @discardableResult
    public func save(_ data: Data, for seriesId: Int) -> SeriesInfo? {
        guard let info = try? JSONDecoder().decode(SeriesInfo.self, from: data) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(seriesId), options: .atomic)
        return info
    }

    /// The kept list; a file that no longer decodes is removed.
    public func load(_ seriesId: Int) -> SeriesInfo? {
        let url = file(seriesId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let info = try? JSONDecoder().decode(SeriesInfo.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return info
    }

    /// Signed out, or series switched off: nothing is kept.
    public func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Which series Start still needs to name the started provider episodes (continue-watching-fresh
/// design 4).
public enum StartedEpisodes {
    /// How many of the most recently played started episodes are looked at.
    public static let limit = 20

    /// The series of the `limit` newest started episodes whose episode list is not `known`, and
    /// that the catalog still has; newest first, each once.
    public static func missingSeries(resume: ResumeStore, known: Set<Int>, catalog: Set<Int>, limit: Int = limit) -> [Int] {
        var result: [Int] = []
        for key in resume.started(prefix: "episode.").prefix(limit) {
            guard let series = resume.series(ofEpisode: String(key.dropFirst("episode.".count))),
                  !known.contains(series), catalog.contains(series), !result.contains(series) else { continue }
            result.append(series)
        }
        return result
    }
}
