import FernsyCore
import FernsyPlayer
import Foundation

/// The actions that assistants (MCP) and Siri (App Intents) offer, with the app's own rules:
/// only visible channels (hidden ones and adult content per Settings left out), the account's
/// stream limit, and never ending a running recording to switch channels.
@MainActor
struct FernsyActions {
    let app: AppModel

    /// Upper bound for one search or listing over channels.
    nonisolated static let channelLimit = AssistantTools.channelLimit

    // MARK: Channels

    /// Channels the app shows: hidden ones and adult content (per Settings) left out.
    var visibleChannels: [LiveChannel] { app.filteredChannels(categoryID: allCategoryID, query: "") }

    func visibleChannel(_ id: Int) -> LiveChannel? { visibleChannels.first { $0.id == id } }

    /// Favourites, then recently watched, without duplicates.
    func favoritesAndRecent(limit: Int = channelLimit) -> [LiveChannel] {
        var seen = Set<Int>()
        let list = (app.filteredChannels(categoryID: favoriteChannelsID, query: "") + app.filteredChannels(categoryID: recentChannelsID, query: ""))
            .filter { seen.insert($0.id).inserted }
        return Array(list.prefix(limit))
    }

    // MARK: Guide

    /// Loads the guides (cache first), waiting at most `timeout` seconds; slower channels keep
    /// what they have (the quick now/next answer, or nothing).
    func loadGuides(_ ids: [Int], timeout: TimeInterval = 20) async {
        await app.epg.load(ids, client: app.client, timeout: timeout)
    }

    func entries(_ channelId: Int) -> [EPGEntry] { app.epg.guide(channelId).entries ?? [] }

    /// The show on now and the next one (from the loaded guide).
    func nowAndNext(_ channelId: Int, at now: Date = Date()) -> (now: EPGEntry?, next: EPGEntry?) {
        app.epg.nowAndNext(channelId, at: now)
    }

    /// Shows whose title or description contains `query`, sorted by start.
    func searchGuide(_ query: String, on channels: [LiveChannel], from: Date = Date(), to: Date = .distantFuture) async -> [(entry: EPGEntry, channel: LiveChannel)] {
        guard !makeSearchKey(query.trimmingCharacters(in: .whitespaces)).isEmpty else { return [] }
        await loadGuides(channels.map(\.id), timeout: 30)
        return app.epg.search(query, on: channels, from: from, to: to)
    }

    // MARK: Recordings

    enum ScheduleResult {
        case planned(Recording?, notice: String?)
        case refused(String)
    }

    /// Schedules a show with the app's padding and stream-limit rules.
    func schedule(_ entry: EPGEntry, on channel: LiveChannel) -> ScheduleResult {
        switch app.recorder.schedule(entry, on: channel) {
        case .refused(let reason): return .refused(reason)
        case .planned(let notice):
            let recording = app.recorder.recordings.first { $0.matches(channelId: channel.id, entry: entry) && $0.isUpcomingOrRunning }
            return .planned(recording, notice: notice)
        }
    }

    /// Records the show on now on `channel` (as the player's record button does).
    func recordNow(_ channel: LiveChannel) async -> (result: ScheduleResult, show: EPGEntry?) {
        await loadGuides([channel.id], timeout: 8)
        let current = nowAndNext(channel.id).now
        switch app.recorder.recordNow(channel, entry: current) {
        case .refused(let reason): return (.refused(reason), current)
        case .planned(let notice):
            let recording = app.recorder.recordings.last { $0.channelId == channel.id && $0.isUpcomingOrRunning }
            return (.planned(recording, notice: notice), current)
        }
    }

    // MARK: Playback

    enum PlayResult {
        case playing
        /// A running recording holds the stream the channel would need.
        case blocked(Recording)
    }

    /// Plays a live channel unless that would end a running recording (no prompt: the person
    /// asking may not be at the Mac).
    func playChannel(_ channel: LiveChannel) -> PlayResult {
        if let first = app.recordingsBlocking(channel.id).first { return .blocked(first) }
        app.play(channel)
        PlayerWindow.show(app)
        return .playing
    }

    /// The live channel the player shows, if any.
    var playingChannel: LiveChannel? {
        guard case .live(let id, _)? = app.nowPlaying?.kind else { return nil }
        return app.channel(id)
    }

    /// Stops playback and closes the player; false when nothing played.
    @discardableResult
    func stopPlayback() -> Bool {
        guard app.nowPlaying != nil else { return false }
        app.nowPlaying = nil
        PlayerWindow.close()
        return true
    }
}
