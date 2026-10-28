import FernsyCore
import FernsyPlayer
import Foundation

/// Start's rows (tvos-start-rows): the rules are FernsyCore's `StartBuilder`, shared with the Mac
/// (mac-start-pages); here only this app's data goes in.
extension TVModel {
    /// Start's inputs from the catalog, Jellyfin, resume positions and recordings.
    var startBuilder: StartBuilder {
        var builder = StartBuilder()
        builder.movies = movies
        builder.series = series
        builder.movieCategories = movieCategories
        builder.seriesCategories = seriesCategories
        builder.jellyfinFilms = jellyfin.films
        builder.jellyfinLatestFilms = jellyfin.latestFilms
        builder.jellyfinLatestSeries = jellyfin.latestSeries
        builder.jellyfinResume = jellyfin.resume
        builder.jellyfinNextUp = jellyfin.nextUp
        let store = jellyfin
        builder.images = .init(poster: { store.posterURL($0) }, thumb: { store.thumbURL($0) }, backdrop: { store.backdropURL($0) })
        builder.resume = resume
        builder.episodeIndex = episodeIndex
        builder.recordings = recorder.recordings.map(Self.startRecording)
        builder.channels = channels
        return builder
    }

    /// Rows from the catalog, built once per catalog change (StartScreen keeps them and adds the
    /// other parts): grouping 30,000 films on every redraw would stall the screen.
    func startRows() -> StartRows { startBuilder.catalogRows() }

    /// Partly watched films and episodes, Jellyfin items and recordings, newest first.
    var continueWatching: [LibraryEntry] { startBuilder.continueWatching() }

    /// The newest IPTV films and series and Jellyfin items, interleaved by date.
    var recentlyAdded: [LibraryEntry] { startBuilder.recentlyAdded() }

    /// Jellyfin's next episodes.
    var nextUpEntries: [LibraryEntry] { startBuilder.nextUp() }

    /// The newest finished recordings.
    var recordingEntries: [LibraryEntry] { startBuilder.finishedRecordings() }

    /// The channels of "Jetzt live" and "Heute Abend".
    var startChannels: (source: LiveSource, channels: [LiveChannel]) {
        StartBuilder.liveChannels(favorites: channels(for: .favorites), recent: channels(for: .recent), all: channels(for: .all))
    }

    /// Tonight's prime time on `channels`, or what starts in the next two hours.
    func tonight(on channels: [LiveChannel], now: Date = Date()) -> (title: String, shows: [(show: EPGEntry, channel: LiveChannel)]) {
        StartBuilder.tonight(on: channels, guide: { self.guide.guide($0).entries ?? [] }, now: now)
    }

    /// A recording of Start's rows, by its id.
    func startRecording(_ id: UUID) -> Recording? { recorder.recordings.first { $0.id == id } }

    static func startRecording(_ recording: Recording) -> StartRecording {
        StartRecording(id: recording.id, title: recording.title, channelId: recording.channelId, channelName: recording.channelName,
                       start: recording.start, recordStart: recording.recordStart, recordEnd: recording.recordEnd,
                       finished: recording.status == .done, failed: recording.status == .failed)
    }
}
