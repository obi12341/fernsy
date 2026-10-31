import Combine
import FernsyCore
import FernsyPlayer
import Foundation
import SwiftUI

/// Audio and subtitle choices remembered per series.
extension AppModel {
    /// Language rules for a playback: the series' remembered choice, else the settings.
    func trackPreferences(for item: PlayItem) -> TrackPreferences {
        guard let key = Self.seriesTrackKey(item), let data = seriesTracks[key],
              let stored = try? JSONDecoder().decode(TrackPreferences.self, from: data) else { return TrackPreferences.settings }
        return stored
    }

    /// The user picked tracks in the player: series episodes keep that choice for the next ones.
    func rememberTracks(_ preferences: TrackPreferences, for item: PlayItem) {
        guard let key = Self.seriesTrackKey(item), let data = try? JSONEncoder().encode(preferences) else { return }
        var all = seriesTracks
        all[key] = data
        var order = (UserDefaults.standard.stringArray(forKey: Self.seriesTracksStore + ".order") ?? []).filter { $0 != key } + [key]
        while order.count > 200 { all[order.removeFirst()] = nil }
        UserDefaults.standard.set(all, forKey: Self.seriesTracksStore)
        UserDefaults.standard.set(order, forKey: Self.seriesTracksStore + ".order")
        AppLog.detail(.player, "remembered for \(key): audio \(preferences.audioLanguage ?? "system"), subtitles \(preferences.subtitles.stored)")
    }

    private var seriesTracks: [String: Data] {
        UserDefaults.standard.dictionary(forKey: Self.seriesTracksStore) as? [String: Data] ?? [:]
    }

    /// Debug runs can keep their memory apart from the user's (IPTV_TRACKSTORE=test).
    static var seriesTracksStore: String {
        #if DEBUG
        if let suffix = ProcessInfo.processInfo.environment["IPTV_TRACKSTORE"] { return "tracks.series.\(suffix)" }
        #endif
        return "tracks.series"
    }

    private static func seriesTrackKey(_ item: PlayItem) -> String? {
        switch item.kind {
        case .episode(_, let seriesId): return "iptv.\(seriesId)"
        case .jellyfin(_, _, let seriesId?): return "jellyfin.\(seriesId)"
        default: return nil
        }
    }
}
