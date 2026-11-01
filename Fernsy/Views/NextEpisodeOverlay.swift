import FernsyCore
import FernsyPlayer
import SwiftUI

/// After an episode: the next one with a countdown.
struct NextEpisodeOverlay: View {
    @ObservedObject var playback: JellyfinPlayback
    let bottomInset: CGFloat
    let play: (JFItem) -> Void
    @State private var remaining = Int(JellyfinPlayback.autoplayDelay)

    var body: some View {
        if let next = playback.nextEpisode, !playback.autoplayCancelled {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next Up").font(.headline).foregroundStyle(.secondary)
                Text(label(next)).font(.title2.weight(.semibold)).lineLimit(2)
                HStack {
                    Button("Play Now (\(remaining))") { play(next) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { playback.cancelAutoplay() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(22)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 32)
            .padding(.bottom, bottomInset)
            .animation(.easeOut(duration: 0.2), value: bottomInset)
            .task(id: playback.autoplayAt) {
                // The countdown belongs to the playback, so the assistant sees the same one.
                guard let deadline = playback.autoplayAt else { return }
                while !Task.isCancelled {
                    remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
                    if remaining == 0 { play(next); return }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
    }

    private func label(_ item: JFItem) -> String { item.episodeLine }
}
