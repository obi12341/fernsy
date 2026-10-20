import Foundation

/// Live categories and channels the user has hidden, for one provider account.
///
/// One small self-contained value (provider ids only, with `modifiedAt`), so a later sync can
/// store it as a single entry per account and merge by set union or last writer. Ids that are
/// missing from the current catalog are kept: the provider may bring them back, and another
/// device may know them.
struct ChannelVisibility: Codable, Equatable {
    var version = 1
    var hiddenCategories: Set<String> = []
    var hiddenChannels: Set<Int> = []
    var modifiedAt = Date(timeIntervalSince1970: 0)

    static let fileName = "visibility.json"

    /// The stored value in an account folder; empty if there is none or it is unreadable.
    static func load(from dir: URL) -> ChannelVisibility {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(fileName)),
              let value = try? decoder.decode(ChannelVisibility.self, from: data) else { return ChannelVisibility() }
        return value
    }

    func save(to dir: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: dir.appendingPathComponent(Self.fileName), options: .atomic)
    }
}
