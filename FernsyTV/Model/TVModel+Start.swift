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
        builder.addJellyfin(jellyfin)
        builder.resume = resume
        builder.episodeIndex = episodeIndex
        builder.recordings = recorder.recordings.map(StartBuilder.recording)
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

    /// What Continue Watching, Next Up and the recordings read: the player closing, positions
    /// from iCloud, Jellyfin's lists and positions, and the recorder's list.
    var startResumeInputs: String {
        let playing = playingVOD != nil || playingRecording != nil
        let recordings = recorder.recordings.map { "\($0.id)\($0.status)" }.joined(separator: ",")
        return "\(playing)|\(resumeRevision)|\(jellyfin.homeRevision)|\(recordings)"
    }

    /// What On Now reads: favourites, recently watched, the channel list and hidden channels.
    var startLiveInputs: String {
        "\(favorites.sorted())|\(recentChannels).\(channels.count).\(visibility.modifiedAt.timeIntervalSince1970)"
    }
}

// MARK: Continue Watching from every device (continue-watching-fresh)

extension TVModel {
    /// Episode lists kept on the device for the signed-in account.
    var seriesInfoStore: SeriesInfoStore? {
        credentials.map {
            SeriesInfoStore(folder: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Fernsy/\($0.accountKey)/series-info", isDirectory: true))
        }
    }

    /// An episode's position was saved: its series goes with it (design 2).
    func noteSeries(of item: VODItem) {
        guard case .episode(let episode, let show) = item else { return }
        resume.setSeries(show.id, forEpisode: episode.id)
    }

    /// A series' episode list is here: Start can name its episodes, and positions saved without
    /// their series (older versions) get it.
    func keep(_ info: SeriesInfo, for seriesId: Int) {
        seriesInfo[seriesId] = info
        if resume.adoptSeries(seriesId, episodes: info.seasons.values.flatMap { $0 }.map(\.id)) > 0 { resumeRevision += 1 }
    }

    /// From the provider, kept on the device; nil when it does not answer.
    func fetchSeriesInfo(_ seriesId: Int) async -> SeriesInfo? {
        guard let data = try? await client?.seriesInfoData(seriesId),
              let info = seriesInfoStore?.save(data, for: seriesId) ?? (try? JSONDecoder().decode(SeriesInfo.self, from: data)) else { return nil }
        freshSeriesInfo.insert(seriesId)
        keep(info, for: seriesId)
        AppLog.detail(.catalog, "episodes of series \(seriesId) loaded and kept")
        return info
    }

    /// The episode lists Start needs for the started episodes: kept ones first, then the provider,
    /// one series after the other (design 4). A failed request is tried at the next trigger.
    func loadStartedSeries() async {
        guard showsIPTVSeries, !series.isEmpty, !loadingStartedSeries else { return }
        let missing = StartedEpisodes.missingSeries(resume: resume, known: Set(seriesInfo.keys), catalog: Set(seriesByID.keys))
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
            guard await fetchSeriesInfo(id) != nil else { continue }
            AppLog.info(.app, "Start: episodes of series \(id) from the provider")
            resumeRevision += 1
        }
    }

    /// The app came back to the front: what the other devices did meanwhile (design 1).
    func refreshFromOtherDevices() {
        AppLog.detail(.app, "back in the front: asking iCloud and Jellyfin again")
        sync.refresh()
        if jellyfin.session != nil, jellyfinHomeThrottle.allow() {
            AppLog.detail(.jellyfin, "Start's rows loaded again")
            Task { await jellyfin.refreshHome() }
        }
        Task { await loadStartedSeries() }
    }
}
