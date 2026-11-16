import FernsyCore
import FernsyPlayer
import SwiftUI

/// What the next-episode card of the Apple TV, iPhone and iPad players shows (Jellyfin at the
/// credits or the end, IPTV episodes at the end); jellyfin-media-segments design 10.
struct UpNextContent: Equatable {
    var image: URL?
    var series: String?
    var line: String
    /// The countdown's end, nil without countdown.
    var deadline: Date?
    var asksStillWatching = false
    /// At the credits: the second button is Watch Credits, otherwise Cancel.
    var atCredits = false

    init(image: URL? = nil, series: String? = nil, line: String, deadline: Date?, asksStillWatching: Bool = false, atCredits: Bool = false) {
        self.image = image
        self.series = series
        self.line = line
        self.deadline = deadline
        self.asksStillWatching = asksStillWatching
        self.atCredits = atCredits
    }

    /// A Jellyfin playback's card.
    @MainActor
    init(card: NextCardState, next: JFItem, deadline: Date?, store: JellyfinStore) {
        self.init(image: store.thumbURL(next).flatMap(URL.init(string:)), series: next.seriesName, line: next.episodeLine,
                  deadline: deadline, asksStillWatching: card.asksStillWatching, atCredits: card.reason == .credits)
    }
}

struct UpNextCard: View {
    let content: UpNextContent
    let play: () -> Void
    let dismiss: () -> Void
    /// Apple TV: Play Now takes focus when the card appears (the player gives it up).
    @FocusState private var playFocused: Bool

    #if os(tvOS)
    private let imageSize = CGSize(width: 288, height: 162)
    private let width: CGFloat = 960
    #else
    private var phone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var imageSize: CGSize { phone ? CGSize(width: 112, height: 63) : CGSize(width: 192, height: 108) }
    // Room for the German buttons ("Jetzt abspielen", "Abspann ansehen") side by side.
    private var width: CGFloat { phone ? 500 : 600 }
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: tv ? 28 : 14) {
            RemoteImage(url: content.image, maxPixel: tv ? 600 : 400) { ArtPlaceholder(seed: content.line) }
                .frame(width: imageSize.width, height: imageSize.height)
                .clipShape(.rect(cornerRadius: tv ? 14 : 10))
            VStack(alignment: .leading, spacing: tv ? 10 : 4) {
                Text(content.asksStillWatching ? "Are you still watching?" : "Next Episode")
                    .font(tv ? .system(size: 22, weight: .semibold) : .subheadline.weight(.semibold)).opacity(0.75)
                    .accessibilityIdentifier("vod.countdown")
                    .accessibilityValue(content.deadline == nil ? "" : "counting")
                if let series = content.series {
                    Text(verbatim: series).font(tv ? .system(size: 22) : .caption).opacity(0.75).lineLimit(1)
                }
                Text(verbatim: content.line).font(tv ? .system(size: 30, weight: .bold) : .headline).lineLimit(2)
                HStack(spacing: tv ? 18 : 10) {
                    Button(action: play) {
                        HStack(spacing: 8) {
                            if let deadline = content.deadline {
                                CountdownRing(deadline: deadline, total: JellyfinPlayback.autoplayDelay, size: tv ? 28 : 20)
                            }
                            Text(content.asksStillWatching ? "Continue Watching" : "Play Now")
                        }
                        .lineLimit(1)
                        .fixedSize()
                    }
                    .accessibilityIdentifier("next.play")
                    .focused($playFocused)
                    #if os(tvOS)
                    .buttonStyle(TVPillStyle())
                    #else
                    .buttonStyle(.borderedProminent)
                    #endif
                    Button(action: dismiss) {
                        Text(content.atCredits ? "Watch Credits" : "Cancel").lineLimit(1).fixedSize()
                    }
                    .accessibilityIdentifier("next.dismiss")
                    #if os(tvOS)
                    .buttonStyle(TVPillStyle(prominent: false))
                    #else
                    .buttonStyle(.bordered)
                    #endif
                }
                .padding(.top, tv ? 8 : 4)
                #if os(tvOS)
                .focusSection()
                #endif
            }
        }
        .padding(tv ? 30 : 16)
        .frame(width: width, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: tv ? 28 : 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("next.card")
        #if os(tvOS)
        .onAppear { DispatchQueue.main.async { playFocused = true } }
        #endif
    }

    private var tv: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }
}

/// Seconds left in a ring that empties.
struct CountdownRing: View {
    let deadline: Date
    let total: TimeInterval
    var size: CGFloat = 20

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let left = max(0, deadline.timeIntervalSince(context.date))
            ZStack {
                Circle().stroke(.primary.opacity(0.3), lineWidth: size / 9)
                Circle().trim(from: 0, to: left / total).stroke(.primary, style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: "\(Int(left.rounded(.up)))").font(.system(size: size * 0.5, weight: .semibold).monospacedDigit())
            }
            .frame(width: size, height: size)
        }
    }
}

/// "Skip Intro" / "Skip Recap" while it plays, or the short note after automatic skipping. On
/// Apple TV it is no focus target: Select in the player skips (the remote keeps seeking).
struct SkipSegmentPill: View {
    let skip: SegmentMarks.Skip?
    let notice: SegmentMarks.SkipKind?
    let action: () -> Void

    var body: some View {
        Group {
            if let skip {
                #if os(tvOS)
                label(skip.kind.skipTitle, prominent: true)
                    .accessibilityIdentifier("player.skip")
                #else
                Button(action: action) { label(skip.kind.skipTitle, prominent: true) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("player.skip")
                #endif
            } else if let notice {
                label(notice.skippedTitle, prominent: false)
                    .accessibilityIdentifier("player.skipped")
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: skip)
        .animation(.easeOut(duration: 0.2), value: notice)
    }

    private func label(_ title: LocalizedStringKey, prominent: Bool) -> some View {
        #if os(tvOS)
        let font = Font.system(size: 26, weight: .semibold), h: CGFloat = 30, v: CGFloat = 16
        #else
        let font = Font.callout.weight(.semibold), h: CGFloat = 16, v: CGFloat = 10
        #endif
        return Label(title, systemImage: "forward.end.fill")
            .font(font)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, h).padding(.vertical, v)
            .background(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .transition(.opacity)
    }
}

extension SegmentMarks.SkipKind {
    var skipTitle: LocalizedStringKey { self == .intro ? "Skip Intro" : "Skip Recap" }
    var skippedTitle: LocalizedStringKey { self == .intro ? "Intro skipped" : "Recap skipped" }
}

extension SegmentPreferences.Skipping {
    /// The setting's choices, as the settings on Apple TV, iPhone and iPad name them.
    var title: LocalizedStringKey {
        switch self {
        case .button: "Show Button"
        case .auto: "Automatically"
        case .never: "Never"
        }
    }
}
