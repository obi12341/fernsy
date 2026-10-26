import FernsyCore
import SwiftUI

/// Placeholder: the live channels by category, each with the show that runs now.
struct ChannelListScreen: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.categories) { category in
                    let channels = model.channels(in: category)
                    if !channels.isEmpty {
                        Section(category.displayName) {
                            ForEach(channels) { channel in
                                ChannelRow(channel: channel, guide: model.guide.guide(channel.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Live TV")
        }
    }
}

private struct ChannelRow: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    /// Observed, so the row shows the show once the guide arrives.
    @ObservedObject var guide: ChannelGuide

    var body: some View {
        Button { model.play(channel) } label: {
            HStack(spacing: 24) {
                Text(verbatim: channel.displayName).font(.headline)
                if let quality = channel.parsed.quality {
                    Text(verbatim: quality).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let show = model.currentShow(on: channel) {
                    Text(verbatim: show.title).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("channel.\(channel.id)")
        .task { await model.loadGuide(for: channel) }
    }
}
