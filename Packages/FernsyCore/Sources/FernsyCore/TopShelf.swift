import Foundation

/// A deep link of the Apple TV app (tvos-top-shelf design 3): `fernsy://play?item=<id>` plays an
/// item, `fernsy://open?item=<id>` opens its page. The ids are the debug tool `play_item`'s, plus
/// live channels and recordings, so the Top Shelf, the URL handling and the tool share them.
public struct TopShelfLink: Equatable, Sendable {
    /// The app's own scheme from its Info.plist: `fernsy`, or `fernsy-dev` in debug builds, so a
    /// tile opens the build that wrote it.
    public static let scheme: String = {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first ?? "fernsy"
    }()

    public enum Action: String, Sendable { case play, open }

    public enum Item: Equatable, Sendable {
        /// `movie:<id>`, an IPTV film.
        case movie(Int)
        /// `episode:<series id>:<episode id>`, an IPTV episode.
        case episode(series: Int, episode: String)
        /// `jellyfin:<id>`, any Jellyfin item.
        case jellyfin(String)
        /// `live:<id>`, a live channel.
        case live(Int)
        /// `recording:<uuid>`, a recording on this Apple TV.
        case recording(UUID)

        /// Parses an id such as `movie:500`; nil for anything else.
        public init?(id: String) {
            let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            switch (parts.first, parts.count) {
            case ("movie", 2): guard let value = Int(parts[1]) else { return nil }; self = .movie(value)
            case ("episode", 3):
                guard let series = Int(parts[1]), !parts[2].isEmpty else { return nil }
                self = .episode(series: series, episode: parts[2])
            case ("jellyfin", 2): guard !parts[1].isEmpty else { return nil }; self = .jellyfin(parts[1])
            case ("live", 2): guard let value = Int(parts[1]) else { return nil }; self = .live(value)
            case ("recording", 2): guard let value = UUID(uuidString: parts[1]) else { return nil }; self = .recording(value)
            default: return nil
            }
        }

        public var id: String {
            switch self {
            case .movie(let id): "movie:\(id)"
            case .episode(let series, let episode): "episode:\(series):\(episode)"
            case .jellyfin(let id): "jellyfin:\(id)"
            case .live(let id): "live:\(id)"
            case .recording(let id): "recording:\(id.uuidString)"
            }
        }

        /// Films, episodes and Jellyfin items have a page; channels and recordings only play.
        public var hasPage: Bool {
            switch self {
            case .movie, .episode, .jellyfin: true
            case .live, .recording: false
            }
        }
    }

    public var action: Action
    public var item: Item

    public init(_ action: Action, _ item: Item) {
        self.action = action
        self.item = item
    }

    /// Parses `fernsy://play?item=…` or `fernsy://open?item=…`; nil for other URLs.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              let action = components.host.flatMap({ Action(rawValue: $0.lowercased()) }),
              let value = components.queryItems?.first(where: { $0.name == "item" })?.value,
              let item = Item(id: value) else { return nil }
        self.init(action, item)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = action.rawValue
        components.queryItems = [URLQueryItem(name: "item", value: item.id)]
        return components.url!
    }
}

/// What the Top Shelf shows (tvos-top-shelf design 1): the Apple TV app writes it into its App
/// Group container from Start's rows, the extension only reads it. Images are files next to it.
public struct TopShelfSnapshot: Codable, Equatable, Sendable {
    /// At most this many items per row (design 4).
    public static let maxItems = 10
    public static let fileName = "topshelf.json"
    /// The images' folder in the container.
    public static let imagesFolder = "TopShelf"

    /// The row; the extension names it in the system's language.
    public enum Kind: String, Codable, Sendable {
        case continueWatching
        /// Start's live row from the favourites, the recently watched or the first channels.
        case favoriteChannels, recentChannels, channels
        case recordings
    }

    /// The tile's shape: 16:9 or square (channel logos).
    public enum Shape: String, Codable, Sendable { case hdtv, square }

    public struct Item: Codable, Equatable, Sendable {
        /// The link id (`TopShelfLink.Item.id`).
        public var id: String
        public var title: String
        public var subtitle: String?
        /// A file name in `imagesFolder`, nil without artwork.
        public var image: String?
        /// 0…1 watched, nil when not started.
        public var progress: Double?
        public var play: URL
        public var display: URL

        public init(id: String, title: String, subtitle: String? = nil, image: String? = nil, progress: Double? = nil, play: URL, display: URL) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.image = image
            self.progress = progress
            self.play = play
            self.display = display
        }
    }

    public struct Section: Codable, Equatable, Sendable {
        public var kind: Kind
        public var shape: Shape
        public var items: [Item]

        public init(kind: Kind, shape: Shape, items: [Item]) {
            self.kind = kind
            self.shape = shape
            self.items = items
        }
    }

    public private(set) var sections: [Section]

    /// Keeps Start's order, cuts each row to `maxItems` and leaves out empty rows.
    public init(sections: [Section]) {
        self.sections = sections.compactMap { section in
            guard !section.items.isEmpty else { return nil }
            var section = section
            section.items = Array(section.items.prefix(Self.maxItems))
            return section
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sections: try container.decode([Section].self, forKey: .sections))
    }

    public var isEmpty: Bool { sections.isEmpty }

    /// Every image file the snapshot names.
    public var imageNames: Set<String> {
        Set(sections.flatMap { $0.items.compactMap(\.image) })
    }

    /// The App Group shared by the app and its extension: `group.<app bundle id>` (design 5). The
    /// extension's bundle id is the app's plus `.topshelf`.
    public static func appGroup(bundleIdentifier: String) -> String {
        let suffix = ".topshelf"
        let app = bundleIdentifier.hasSuffix(suffix) ? String(bundleIdentifier.dropLast(suffix.count)) : bundleIdentifier
        return "group." + app
    }

    /// Where the snapshot and its images live: `Library/Caches` of the App Group container. tvOS
    /// lets apps write only to caches, also in a shared container; its top level is read-only.
    /// nil when the build has no App Group (unsigned builds).
    public static func directory(bundleIdentifier: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup(bundleIdentifier: bundleIdentifier))?
            .appendingPathComponent("Library/Caches", isDirectory: true)
    }

    public static func encode(_ snapshot: TopShelfSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> TopShelfSnapshot {
        try JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }
}
