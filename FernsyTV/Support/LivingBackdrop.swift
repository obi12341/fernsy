import SwiftUI
import UIKit

/// The large entry's backdrop (tvos-living-hero): while `active`, it zooms and pans slowly (Ken
/// Burns) and cross-fades to the title's next backdrop every few seconds; inactive, it rests on
/// the current frame. The motion runs on its own clock that only advances while active, so focus
/// leaving and coming back continues where it stopped instead of jumping.
struct LivingBackdrop: View {
    let urls: [URL]
    let active: Bool
    let seed: String
    var maxPixel = 1920

    /// Zoom from 1.0 to 1.08 over `zoomSeconds`, then back; another backdrop every `holdSeconds`.
    static let zoomSeconds = 20.0
    static let holdSeconds = 8.0
    static let fadeSeconds = 1.2
    static let zoom = 0.08
    static let pan = 0.02

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Loaded backdrops in the order of `urls`; the cycle runs over these only, so a backdrop
    /// still loading is never faded to.
    @State private var images: [URL: UIImage] = [:]
    /// Active time before the current active span, and when that span began.
    @State private var elapsed: TimeInterval = 0
    @State private var since: Date?

    var body: some View {
        GeometryReader { size in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
                frame(at: clock(context.date), size: size.size)
            }
        }
        .onChange(of: active, initial: true) { _, now in
            if now { since = .now } else if let since { elapsed += Date.now.timeIntervalSince(since); self.since = nil }
        }
        // A new entry starts its motion over; more backdrops for the same one keep the loaded.
        .onChange(of: urls) { images = images.filter { urls.contains($0.key) } }
        .onChange(of: urls.first) { elapsed = 0; since = active ? .now : nil }
        // The first backdrop at once, the others only once the entry has focus.
        .task(id: urls.first) { await load(urls.prefix(1)) }
        .task(id: "\(active) \(urls.map(\.absoluteString))") { if active { await load(urls.dropFirst()) } }
    }

    private func clock(_ date: Date) -> TimeInterval {
        elapsed + (since.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    @ViewBuilder private func frame(at time: TimeInterval, size: CGSize) -> some View {
        let shown = urls.filter { images[$0] != nil }
        if shown.isEmpty {
            ArtPlaceholder(seed: seed)
        } else {
            let step = Int(time / Self.holdSeconds)
            let current = step % shown.count
            // Within the first moments of a step the previous backdrop still fades out.
            let fade = min(1, (time - Double(step) * Self.holdSeconds) / Self.fadeSeconds)
            ZStack {
                if step > 0, fade < 1, shown.count > 1 {
                    let previous = (step - 1) % shown.count
                    layer(shown[previous], index: previous, time: time, size: size)
                }
                layer(shown[current], index: current, time: time, size: size)
                    .opacity(step > 0 && shown.count > 1 ? fade : 1)
            }
        }
    }

    private func layer(_ url: URL, index: Int, time: TimeInterval, size: CGSize) -> some View {
        // Back and forth: 0 → 1 over zoomSeconds, then back, eased at both ends.
        let progress = reduceMotion ? 0 : (1 - cos(time / Self.zoomSeconds * .pi)) / 2
        // Each backdrop pans its own way.
        let angle = Double(index) * 2.4 + 0.6
        return Image(uiImage: images[url]!).resizable().scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(1 + Self.zoom * progress)
            .offset(x: cos(angle) * Self.pan * size.width * progress, y: sin(angle) * Self.pan * size.height * progress)
            .clipped()
    }

    private func load(_ list: some Sequence<URL>) async {
        for url in list where images[url] == nil {
            if let image = await ImagePipeline.shared.image(url, maxPixel: maxPixel) { images[url] = image }
            if Task.isCancelled { return }
        }
    }
}
