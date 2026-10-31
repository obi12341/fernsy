import FernsyCore
import FernsyPlayer
import Foundation

/// A page Start opens for a deep link (tvos-top-shelf design 3). TVModel cannot name the screens'
/// `DetailTarget`, so it hands over Start's own target.
struct PageRequest: Identifiable, Equatable {
    let id = UUID()
    let target: LibraryEntry.Target

    static func == (a: PageRequest, b: PageRequest) -> Bool { a.id == b.id }
}

/// Items by their link id (`TopShelfLink.Item`): the Top Shelf's `fernsy://` URLs and the debug
/// tool `play_item` share them (tvos-top-shelf design 3).
extension TVModel {
    struct LinkError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Plays a film or episode from its resume position (unless `fromStart`), a Jellyfin item, a
    /// channel live or a recording from where the user stopped.
    func play(_ item: TopShelfLink.Item, fromStart: Bool = false) async throws {
        switch item {
        case .movie(let id):
            guard let movie = moviesByID[id] else { throw LinkError(message: "No film \(item.id)") }
            play(.movie(movie), fromStart: fromStart)
        case .episode(let seriesId, let episodeId):
            guard let show = seriesByID[seriesId], let info = await seriesDetails(show),
                  let episode = info.seasons.values.flatMap({ $0 }).first(where: { $0.id == episodeId }) else {
                throw LinkError(message: "No episode \(item.id)")
            }
            play(.episode(episode, show), fromStart: fromStart)
        case .jellyfin(let id):
            guard let jfItem = await jellyfinItem(id) else { throw LinkError(message: "No Jellyfin item \(id)") }
            play(.jellyfin(jfItem), fromStart: fromStart)
        case .live(let id):
            guard let channel = channels.first(where: { $0.id == id }) else { throw LinkError(message: "No channel \(id)") }
            play(channel)
        case .recording(let id):
            guard let recording = startRecording(id) else { throw LinkError(message: "No recording \(id)") }
            play(recording)
        }
    }

    /// Opens the item's page on Start: a film's, an episode's series, a Jellyfin item's (an
    /// episode's series). Channels and recordings have no page and play.
    func open(_ item: TopShelfLink.Item) async throws {
        let target: LibraryEntry.Target
        switch item {
        case .movie(let id):
            guard let movie = moviesByID[id] else { throw LinkError(message: "No film \(item.id)") }
            target = .movie(movie)
        case .episode(let seriesId, _):
            guard let show = seriesByID[seriesId] else { throw LinkError(message: "No series \(seriesId)") }
            target = .series(show)
        case .jellyfin(let id):
            guard var jfItem = await jellyfinItem(id) else { throw LinkError(message: "No Jellyfin item \(id)") }
            if jfItem.type == "Episode", let seriesId = jfItem.seriesId, let show = await jellyfinItem(seriesId) { jfItem = show }
            target = .jellyfin(jfItem)
        case .live, .recording:
            try await play(item)
            return
        }
        stop()
        stopPreview()
        pageRequest = PageRequest(target: target)
    }

    /// Loaded fresh: the server keeps the resume position.
    private func jellyfinItem(_ id: String) async -> JFItem? {
        guard jellyfin.session != nil else { return nil }
        await jellyfin.loadDetail(id)
        return jellyfin.details[id]
    }

    /// A `fernsy://play` or `fernsy://open` URL. It waits until the item is there – sign-in, the
    /// catalog, Jellyfin – as IPTV_AUTOPLAY waits for the catalog, at most a minute.
    func handle(url: URL) {
        guard let link = TopShelfLink(url: url) else {
            AppLog.warning(.app, "unknown link \(url.absoluteString)")
            return
        }
        AppLog.info(.app, "link: \(link.action.rawValue) \(link.item.id)")
        linkTask?.cancel()
        linkTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(60)
            while let self, !self.canResolve(link.item) {
                guard Date() < deadline, !Task.isCancelled else {
                    AppLog.warning(.app, "link \(link.item.id): not found after waiting for the catalog")
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let self, !Task.isCancelled else { return }
            do {
                switch link.action {
                case .play: try await self.play(link.item)
                case .open: try await self.open(link.item)
                }
            } catch {
                AppLog.warning(.app, "link \(link.item.id): \(error.localizedDescription)")
            }
            self.linkTask = nil
        }
    }

    /// Whether what the item needs has loaded: its list, or the Jellyfin account.
    private func canResolve(_ item: TopShelfLink.Item) -> Bool {
        guard signIn != .signingIn, !signingInFromICloud else { return false }
        switch item {
        case .movie(let id): return moviesByID[id] != nil
        case .episode(let seriesId, _): return seriesByID[seriesId] != nil
        case .jellyfin: return jellyfin.session != nil
        case .live(let id): return channels.contains { $0.id == id }
        case .recording(let id): return startRecording(id) != nil
        }
    }
}
