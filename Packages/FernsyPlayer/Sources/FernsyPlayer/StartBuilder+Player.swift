import FernsyCore
import Foundation

/// Start's inputs that the Mac, Apple TV and iOS fill the same way (code-structure-cleanup 3.5).
public extension StartBuilder {
    /// Jellyfin's lists and its artwork URLs.
    @MainActor
    mutating func addJellyfin(_ store: JellyfinStore) {
        jellyfinFilms = store.films
        jellyfinLatestFilms = store.latestFilms
        jellyfinLatestSeries = store.latestSeries
        jellyfinResume = store.resume
        jellyfinNextUp = store.nextUp
        images = .init(poster: { store.posterURL($0) }, thumb: { store.thumbURL($0) }, backdrop: { store.backdropURL($0) })
    }

    /// A recording as Start shows it.
    static func recording(_ recording: Recording) -> StartRecording {
        StartRecording(id: recording.id, title: recording.title, channelId: recording.channelId, channelName: recording.channelName,
                       start: recording.start, recordStart: recording.recordStart, recordEnd: recording.recordEnd,
                       finished: recording.status == .done, failed: recording.status == .failed)
    }
}
