import FernsyCore
import FernsyPlayer
import Foundation

/// "1 hr 52 min" or "48 min".
enum Runtime {
    static func text(seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? String(localized: "\(minutes / 60) hr \(minutes % 60) min") : String(localized: "\(minutes) min")
    }
}

/// What the film and series pages of Apple TV and iOS show besides their layout
/// (code-structure-cleanup 3.6): the film's facts, position and duration, and the episode rows.
enum LibraryDetail {
    enum Film { case iptv(Movie), jellyfin(JFItem) }

    struct EpisodeEntry: Identifiable {
        let id: String
        let title: String
        let number: String
        let label: String
        let image: URL?
        let progress: Double?
        let watched: Bool
        let item: VODItem
    }

    /// Year, genre, runtime and rating, from Jellyfin or the provider's details.
    static func facts(_ film: Film, jellyfin jfItem: JFItem?, details: MovieDetails?) -> [String] {
        var list: [String] = []
        if let item = jfItem {
            if let year = item.productionYear { list.append("\(year)") }
            if let genre = item.genres?.first { list.append(genre) }
            if let seconds = item.runTimeSeconds { list.append(Runtime.text(seconds: seconds)) }
            if let rating = item.communityRating { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        } else if case .iptv(let movie) = film {
            if let year = details?.releaseDate?.prefix(4), !year.isEmpty { list.append(String(year)) }
            if let genre = details?.genre?.split(separator: ",").first { list.append(String(genre).trimmingCharacters(in: .whitespaces)) }
            if let duration = details?.duration, !duration.isEmpty { list.append(duration) }
            if let rating = movie.rating, rating > 0 { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        }
        return list
    }

    /// Where the user stopped, in seconds.
    @MainActor
    static func position(_ film: Film, jellyfin jfItem: JFItem?, model: TVModel) -> Double {
        switch film {
        case .iptv(let movie): model.resume.position(ResumeStore.movieKey(movie.id))
        case .jellyfin(let item): (jfItem ?? item).positionSeconds
        }
    }

    /// The film's length in seconds (IPTV: known only once it was played).
    @MainActor
    static func duration(_ film: Film, jellyfin jfItem: JFItem?, model: TVModel) -> Double {
        switch film {
        case .iptv(let movie):
            let key = ResumeStore.movieKey(movie.id)
            return model.resume.fraction(key).map { model.resume.position(key) / $0 } ?? 0
        case .jellyfin(let item): return ((jfItem ?? item).runTimeSeconds ?? 0)
        }
    }

    @MainActor
    static func entry(_ episode: Episode, _ series: Series, _ model: TVModel) -> EpisodeEntry {
        let key = ResumeStore.episodeKey(episode.id)
        let runtime = episode.durationSeconds.map { " · " + Runtime.text(seconds: Double($0)) } ?? ""
        return EpisodeEntry(id: episode.id, title: episode.title, number: episode.code + runtime,
                            label: episode.code, image: (episode.image ?? series.cover).flatMap(URL.init(string:)),
                            progress: model.resume.fraction(key), watched: model.resume.isWatched(key), item: .episode(episode, series))
    }

    @MainActor
    static func entry(_ item: JFItem) -> EpisodeEntry {
        let runtime = item.runTimeSeconds.map { " · " + Runtime.text(seconds: $0) } ?? ""
        let label = item.episodeCode ?? ""
        let share = item.userData?.playedPercentage.map { $0 / 100 }
        return EpisodeEntry(id: item.id, title: item.name, number: label.isEmpty ? String(runtime.dropFirst(3)) : label + runtime, label: label,
                            image: TVModel.shared.jellyfin.thumbURL(item).flatMap(URL.init(string:)),
                            progress: share.flatMap { $0 > 0 ? $0 : nil }, watched: item.userData?.played == true, item: .jellyfin(item))
    }
}
