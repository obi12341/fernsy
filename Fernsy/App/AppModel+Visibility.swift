import Combine
import FernsyCore
import FernsyPlayer
import Foundation
import SwiftUI

extension AppModel {
    var hasHiddenChannels: Bool { !visibility.hiddenCategories.isEmpty || !visibility.hiddenChannels.isEmpty }
    // MARK: Hidden categories and channels

    func isHidden(_ channel: LiveChannel) -> Bool { visibility.isHidden(channel) }

    func isCategoryHidden(_ id: String) -> Bool { visibility.hiddenCategories.contains(id) }

    func isChannelHidden(_ id: Int) -> Bool { visibility.hiddenChannels.contains(id) }

    func setCategory(_ id: String, hidden: Bool) {
        guard isCategoryHidden(id) != hidden else { return }
        var value = visibility
        if hidden { value.hiddenCategories.insert(id) } else { value.hiddenCategories.remove(id) }
        storeVisibility(value)
    }

    func setChannel(_ id: Int, hidden: Bool) {
        guard isChannelHidden(id) != hidden else { return }
        var value = visibility
        if hidden { value.hiddenChannels.insert(id) } else { value.hiddenChannels.remove(id) }
        storeVisibility(value)
    }

    /// Edit mode's "Show All": nothing hidden any more.
    func showAllChannels() {
        guard !visibility.hiddenCategories.isEmpty || !visibility.hiddenChannels.isEmpty else { return }
        var value = visibility
        value.hiddenCategories = []
        value.hiddenChannels = []
        storeVisibility(value)
    }


    private func storeVisibility(_ value: ChannelVisibility) {
        var value = value
        value.modifiedAt = Date()
        visibility = value
        if let dir = cacheDirectory { value.save(to: dir) }
        if let key = credentials?.accountKey { sync.push(value, as: SyncStore.accountName(key, "visibility"), modifiedAt: value.modifiedAt) }
    }

    /// The signed-in account's choice; signed out, nothing is hidden (the file stays).
    func loadVisibility() {
        visibility = cacheDirectory.map(ChannelVisibility.load) ?? ChannelVisibility()
        AppLog.detail(.app, "\(credentials?.accountKey ?? "-"): \(visibility.hiddenCategories.count) categories, \(visibility.hiddenChannels.count) channels hidden")
        pullVisibility()
    }

    func updateVisibleCounts() {
        var counts: [String: Int] = [:]
        for channel in channels where !isHidden(channel) { counts[channel.categoryId ?? "", default: 0] += 1 }
        visibleChannelCounts = counts
        visibleChannelTotal = counts.values.reduce(0, +)
        SiriIndex.schedule(self)
    }

    /// Teaches Siri which channels are watched (suggestions, "Schalte Fernsy auf …").
    func donateChannel(_ id: Int) {
        guard SiriIndex.isEnabled, let channel = channel(id) else { return }
        let entity = ChannelEntity(channel, app: self)
        Task { _ = try? await PlayChannelIntent(channel: entity).donate() }
    }

    // MARK: Favorites

    func isFavorite(_ key: String) -> Bool { favorites.contains(key) }

    func noteRecent(_ channelId: Int) {
        recentChannels = LiveRules.noting(channelId, in: recentChannels)
        // Test runs (no keychain) keep it in memory: they share the installed app's defaults.
        if !Self.skipKeychain { UserDefaults.standard.set(recentChannels, forKey: LiveRules.recentKey) }
    }

    /// Context menu: takes a channel out of "Zuletzt gesehen".
    func removeRecent(_ channelId: Int) {
        recentChannels.removeAll { $0 == channelId }
        if !Self.skipKeychain { UserDefaults.standard.set(recentChannels, forKey: LiveRules.recentKey) }
    }

    func toggleFavorite(_ key: String) {
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
        #if DEBUG
        if debugFavoritesInMemory { return }
        #endif
        UserDefaults.standard.set(Array(favorites), forKey: LiveRules.favoritesKey)
    }
}
