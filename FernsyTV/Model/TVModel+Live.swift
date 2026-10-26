import FernsyCore
import FernsyPlayer
import Foundation

/// The live lists of Apple TV, with the Mac's rules (LiveRules): favourites, recently watched,
/// hidden and adult categories and channels, and the categories pinned into Live TV's column.
/// Favourites and the history use the Mac's UserDefaults keys; the per-account values live in
/// UserDefaults too, because tvOS keeps nothing else for sure (design D of tvos-live).
extension TVModel {
    /// What Live TV's category column can show.
    enum LiveSource: Hashable {
        case favorites, recent, all
        case category(String)
    }

    // MARK: Loading and storing

    private var accountKey: String? { credentials?.accountKey }

    private func key(_ name: String) -> String? { accountKey.map { "\(name).\($0)" } }

    /// Reads the stored lists for the signed-in account. Test runs without the keychain keep
    /// everything in memory (they share the defaults with nothing, but stay repeatable).
    func loadLiveState() {
        guard !Self.skipKeychain else { return }
        let defaults = UserDefaults.standard
        favorites = Set(defaults.stringArray(forKey: LiveRules.favoritesKey) ?? [])
        recentChannels = defaults.array(forKey: LiveRules.recentKey) as? [Int] ?? []
        visibility = ChannelVisibility.decoded(key("live.visibility").flatMap { defaults.data(forKey: $0) })
        pinned = PinnedCategories.decoded(key("live.pinned").flatMap { defaults.data(forKey: $0) })
    }

    private func store(_ data: Data?, as name: String) {
        guard !Self.skipKeychain, let key = key(name) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: Favourites and history

    func isFavorite(_ channel: LiveChannel) -> Bool { favorites.contains(LiveRules.favoriteKey(channel: channel.id)) }

    func toggleFavorite(_ channel: LiveChannel) {
        let key = LiveRules.favoriteKey(channel: channel.id)
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
        if !Self.skipKeychain { UserDefaults.standard.set(Array(favorites), forKey: LiveRules.favoritesKey) }
    }

    func noteRecent(_ channelId: Int) {
        recentChannels = LiveRules.noting(channelId, in: recentChannels)
        if !Self.skipKeychain { UserDefaults.standard.set(recentChannels, forKey: LiveRules.recentKey) }
    }

    // MARK: Hiding and pinning

    func isHidden(_ channel: LiveChannel) -> Bool {
        visibility.isHidden(channel) || isAdult(channel)
    }

    func setHidden(_ channel: LiveChannel, _ hidden: Bool) {
        var value = visibility
        if hidden { value.hiddenChannels.insert(channel.id) } else { value.hiddenChannels.remove(channel.id) }
        value.modifiedAt = Date()
        visibility = value
        store(value.encoded, as: "live.visibility")
    }

    func isCategoryHidden(_ category: XCategory) -> Bool { visibility.hiddenCategories.contains(category.id) }

    func setHidden(_ category: XCategory, _ hidden: Bool) {
        var value = visibility
        if hidden { value.hiddenCategories.insert(category.id) } else { value.hiddenCategories.remove(category.id) }
        value.modifiedAt = Date()
        visibility = value
        store(value.encoded, as: "live.visibility")
        if hidden && pinned.contains(category.id) { setPinned(category, false) }
    }

    func isPinned(_ category: XCategory) -> Bool { pinned.contains(category.id) }

    func setPinned(_ category: XCategory, _ value: Bool) {
        var list = pinned
        list.set(category.id, pinned: value)
        pinned = list
        store(list.encoded, as: "live.pinned")
    }

    /// Adult content stays hidden on Apple TV, as with the Mac's default setting.
    func isAdult(_ channel: LiveChannel) -> Bool {
        channel.isAdult || adultCategoryIDs.contains(channel.categoryId ?? "")
    }

    var adultCategoryIDs: Set<String> { Set(categories.filter(LiveRules.isAdultCategory).map(\.id)) }

    // MARK: Lists

    /// Categories the user can see (not hidden, not adult), in the provider's order.
    var visibleCategories: [XCategory] {
        categories.filter { !LiveRules.isAdultCategory($0) && !isCategoryHidden($0) }
    }

    var pinnedCategories: [XCategory] {
        pinned.categories.compactMap { id in visibleCategories.first { $0.id == id } }
    }

    /// The visible channels of a source, in its order.
    func channels(for source: LiveSource) -> [LiveChannel] {
        switch source {
        case .favorites: channels.filter { isFavorite($0) && !isHidden($0) }
        case .recent: recentChannels.compactMap { id in channels.first { $0.id == id } }.filter { !isHidden($0) }
        case .all: channels.filter { !isHidden($0) }
        case .category(let id): channels.filter { $0.categoryId == id && !isHidden($0) }
        }
    }

    /// The strip's channels: the zap source's visible ones, starting at the playing channel
    /// (the whole list if the source has none left, as zapping on the Mac).
    var zapChannels: [LiveChannel] {
        var list = channels(for: zapSource)
        if list.isEmpty { list = channels(for: .all) }
        guard let playing, let index = list.firstIndex(where: { $0.id == playing.id }) else { return list }
        return Array(list[index...] + list[..<index])
    }

    /// Zapping to `channel`: when a recording holds the connection it needs, asks first, as the
    /// Mac does; the recording stops only if the user agrees.
    func zap(to channel: LiveChannel) async {
        let held = tuners.blockers(for: channel.id, as: .player).flatMap(\.owners).compactMap { owner -> Recording? in
            guard case .recording(let id) = owner else { return nil }
            return recorder.recordings.first { $0.id == id && $0.status == .recording }
        }
        if let recording = held.first {
            let stop = await ask(
                title: String(localized: "“\(recording.title)” Is Being Recorded"),
                message: String(localized: "Your account allows \(maxConnections) stream(s) at a time. Switching to \(channel.displayName) stops the recording."),
                confirm: String(localized: "Stop Recording and Switch"), cancel: String(localized: "Keep Recording"),
                timeout: 60, timeoutAnswer: false)
            guard stop else { return }
            for recording in held { recorder.stop(recording.id) }
        }
        play(channel)
    }

    /// The upcoming shows after the current one, once the guide is loaded.
    func nextShows(on channel: LiveChannel, count: Int = 2, at date: Date = Date()) -> [EPGEntry] {
        Array((guide.guide(channel.id).entries ?? []).filter { $0.start > date }.prefix(count))
    }
}
