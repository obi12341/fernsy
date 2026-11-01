import FernsyCore
import Foundation

/// What the player window should show.
struct PlayItem: Equatable {
    enum Kind: Equatable {
        case live(channelId: Int, categoryId: String?)
        case movie(id: Int)
        case episode(id: String, seriesId: Int)
        case recording(id: UUID)
        /// A recording in Fernsy Cloud, by its cloud id.
        case cloud(id: String)
        /// A Jellyfin film or episode, started at `startAt` seconds.
        case jellyfin(itemId: String, startAt: Double, seriesId: String? = nil)
        /// A past show from the channel's archive (catch-up).
        case archive(channelId: Int, start: Date, end: Date)
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let url: URL

    var isLive: Bool {
        if case .live = kind { return true }
        return false
    }

    var resumeKey: String? {
        switch kind {
        case .live: return nil
        case .movie(let id): return ResumeStore.movieKey(id)
        case .episode(let id, _): return ResumeStore.episodeKey(id)
        case .recording(let id): return ResumeStore.recordingKey(id)
        case .cloud(let id): return ResumeStore.cloudKey(id)
        case .jellyfin: return nil // resume positions live on the server
        case .archive: return nil  // archives expire within days
        }
    }

    /// What is played, for the log (no URL: it carries the account's credentials).
    var logDescription: String {
        switch kind {
        case .live(let id, _): return "channel \(id)"
        case .movie(let id): return "film \(id)"
        case .episode(let id, _): return "episode \(id)"
        case .recording: return "recording"
        case .cloud: return "cloud recording"
        case .jellyfin(let id, let startAt, _): return "Jellyfin item \(id)\(startAt > 0 ? " at \(Int(startAt)) s" : "")"
        case .archive(let id, let start, _): return "archive of channel \(id) from \(start.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}
