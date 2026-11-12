import FernsyCore
import SwiftUI

/// One line of text that is cut off with an ellipsis at rest and, while `active`, slides to its
/// end and back so that all of it can be read (tvos-guide-name-ticker). A text that fits never
/// moves, and with Reduce Motion nothing does. Only an active text is measured and runs a clock,
/// so a list of resting ones costs what plain texts cost.
struct TickerText: View {
    let text: String
    let font: Font
    let active: Bool
    /// The text started to slide: it is active and does not fit.
    var started: () -> Void = {}

    /// Where the text continues beyond its room, it fades out over this many points.
    private static let fade: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The text's full width, measured while active.
    @State private var width: CGFloat = 0
    /// When the text started to slide; none while it rests or fits.
    @State private var since: Date?

    /// IPTV_TESTREDUCEMOTION=1 (debug): as with Reduce Motion on, which a UI test cannot switch.
    private var reduced: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_TESTREDUCEMOTION"] == "1" { return true }
        #endif
        return reduceMotion
    }

    private var sliding: Bool { active && !reduced && since != nil }

    var body: some View {
        // The shortened text keeps its place in the layout; the sliding one is drawn over it.
        Text(verbatim: text).font(font).lineLimit(1)
            .opacity(sliding ? 0 : 1)
            .overlay(alignment: .leading) {
                if active && !reduced {
                    GeometryReader { room in slide(room: room.size) }
                }
            }
            .onChange(of: active) { _, now in if !now { since = nil } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
            .accessibilityValue(sliding ? "moving" : "")
            .accessibilityAddTraits(.isStaticText)
    }

    private func slide(room: CGSize) -> some View {
        let distance = Double(width - room.width)
        let fits = distance < 1
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: fits)) { context in
            let offset = TickerMotion.offset(after: context.date.timeIntervalSince(since ?? context.date), distance: distance)
            Text(verbatim: text).font(font).lineLimit(1).fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .offset(x: -offset)
                .frame(width: room.width, height: room.height, alignment: .leading)
                .mask { edges(left: offset, right: distance - offset) }
                .opacity(fits ? 0 : 1)
        }
        .onChange(of: fits, initial: true) { _, fits in
            since = fits ? nil : .now
            if !fits { started() }
        }
    }

    /// Opaque in the middle; an edge fades out as far as text continues beyond it.
    private func edges(left: Double, right: Double) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(1 - min(1, max(0, left) / Self.fade)), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(1 - min(1, max(0, right) / Self.fade))], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
        }
    }
}
