import FernsyCore
import FernsyPlayer
import SwiftUI

/// The next episode at the final credits or the end, with a countdown ring around Play Now
/// (jellyfin-media-segments, design 10). The countdown itself runs in the playback.
struct NextEpisodeOverlay: View {
    @ObservedObject var playback: JellyfinPlayback
    @EnvironmentObject private var jellyfin: JellyfinStore
    let bottomInset: CGFloat

    var body: some View {
        if let card = playback.card, let next = playback.nextEpisode {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage(url: jellyfin.thumbURL(next), maxPixel: 600) { Rectangle().fill(.white.opacity(0.08)) }
                    .frame(width: 176, height: 99)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.asksStillWatching ? "Are you still watching?" : "Next Episode")
                        .font(.headline).foregroundStyle(.secondary)
                    if let series = next.seriesName { Text(verbatim: series).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                    Text(verbatim: next.episodeLine).font(.title3.weight(.semibold)).lineLimit(2)
                    HStack(spacing: 10) {
                        Button { playback.playNext() } label: {
                            HStack(spacing: 8) {
                                if let at = playback.autoplayAt { CountdownRing(deadline: at, total: JellyfinPlayback.autoplayDelay) }
                                Text(card.asksStillWatching ? "Continue Watching" : "Play Now")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("next.play")
                        Button(card.reason == .credits ? "Watch Credits" : "Cancel") { playback.cancelAutoplay() }
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier("next.dismiss")
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .frame(maxWidth: 520, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("next.card")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 32)
            .padding(.bottom, bottomInset)
            .animation(.easeOut(duration: 0.2), value: bottomInset)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
}

/// Seconds left in a ring that empties.
private struct CountdownRing: View {
    let deadline: Date
    let total: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let left = max(0, deadline.timeIntervalSince(context.date))
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 2.5)
                Circle().trim(from: 0, to: left / total).stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: "\(Int(left.rounded(.up)))").font(.caption2.monospacedDigit().weight(.semibold))
            }
            .frame(width: 20, height: 20)
            .accessibilityLabel(Text("\(Int(left.rounded(.up))) seconds"))
        }
    }
}

/// "Skip Intro" / "Skip Recap" while it plays, and the short note after automatic skipping.
struct SkipSegmentOverlay: View {
    @ObservedObject var playback: JellyfinPlayback
    let bottomInset: CGFloat

    var body: some View {
        Group {
            if let skip = playback.activeSkip {
                Button { playback.skipSegment() } label: {
                    Label(skip.kind == .intro ? "Skip Intro" : "Skip Recap", systemImage: "forward.end.fill")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.22))
                .accessibilityIdentifier("player.skip")
                .transition(.opacity)
            } else if let kind = playback.skippedNotice {
                Label(kind == .intro ? "Intro skipped" : "Recap skipped", systemImage: "forward.end.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("player.skipped")
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 32)
        .padding(.bottom, bottomInset)
        .animation(.easeOut(duration: 0.2), value: playback.activeSkip)
        .animation(.easeOut(duration: 0.2), value: playback.skippedNotice)
    }
}
