import FernsyCore
import Foundation
import TVServices

/// Fernsy's Top Shelf on the Apple TV Home Screen (tvos-top-shelf). The app writes what to show
/// into the App Group container (`TopShelfSnapshot`, images next to it); this only reads it. No
/// snapshot or an empty one: nil, and tvOS shows the static Top Shelf image.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let container = TopShelfSnapshot.directory(bundleIdentifier: Bundle.main.bundleIdentifier ?? ""),
              let data = try? Data(contentsOf: container.appendingPathComponent(TopShelfSnapshot.fileName)),
              let snapshot = try? TopShelfSnapshot.decode(data), !snapshot.isEmpty else { return nil }
        let images = container.appendingPathComponent(TopShelfSnapshot.imagesFolder, isDirectory: true)
        let sections = snapshot.sections.map { section in
            let collection = TVTopShelfItemCollection(items: section.items.map { Self.item($0, shape: section.shape, images: images) })
            collection.title = Self.title(section.kind)
            return collection
        }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private static func item(_ entry: TopShelfSnapshot.Item, shape: TopShelfSnapshot.Shape, images: URL) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: entry.id)
        item.imageShape = shape == .square ? .square : .hdtv
        // The subtitle (time left, the show on now) goes with the title: sectioned items have one line.
        item.title = entry.subtitle.map { $0.isEmpty ? entry.title : "\(entry.title) · \($0)" } ?? entry.title
        if let progress = entry.progress { item.playbackProgress = progress }
        if let name = entry.image {
            // One file, drawn at the 2x size; tvOS scales it for 1x screens.
            let url = images.appendingPathComponent(name)
            item.setImageURL(url, for: .screenScale1x)
            item.setImageURL(url, for: .screenScale2x)
        }
        item.playAction = TVTopShelfAction(url: entry.play)
        item.displayAction = TVTopShelfAction(url: entry.display)
        return item
    }

    private static func title(_ kind: TopShelfSnapshot.Kind) -> String {
        switch kind {
        case .continueWatching: String(localized: "Continue Watching", comment: "Top Shelf row: films and episodes in progress")
        case .favoriteChannels: String(localized: "Favorite Channels", comment: "Top Shelf row: the favourite live channels")
        case .recentChannels: String(localized: "Recently Watched", comment: "Top Shelf row: the recently watched live channels")
        case .channels: String(localized: "On Now", comment: "Top Shelf row: live channels without favourites or history")
        case .recordings: String(localized: "Your Recordings", comment: "Top Shelf row: finished recordings")
        }
    }
}
