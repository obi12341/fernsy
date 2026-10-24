import SwiftUI

/// Live TV's timeline over the timeshift buffer: clock times below, the shows' starts and
/// titles above, a red dot at the live end. Dragging or clicking seeks; letting go at the
/// end returns to live.
struct LiveTimeline: View {
    @ObservedObject var progress: PlaybackProgress
    /// Playable buffer time range (oldest second … live edge).
    let range: ClosedRange<Double>
    let entries: [EPGEntry]
    let onSeek: (Double) -> Void
    let onGoLive: () -> Void
    var onDragging: (Bool) -> Void = { _ in }
    var onActivity: () -> Void = {}

    @State private var scrubbing: Double?

    private var shown: Double {
        if let scrubbing { return scrubbing }
        return progress.followsLive ? range.upperBound : min(max(progress.position, range.lowerBound), range.upperBound)
    }

    /// Clock time of a buffer time.
    private func wall(_ t: Double) -> Date {
        (progress.wallClock ?? Date()).addingTimeInterval(t - progress.position)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = max(1, range.upperBound - range.lowerBound)
            let x = { (t: Double) -> CGFloat in CGFloat((t - range.lowerBound) / span) * width }
            let start = wall(range.lowerBound), end = wall(range.upperBound)
            let starts = entries.filter { $0.start > start && $0.start < end }
            ZStack(alignment: .topLeading) {
                // Show titles above, at their start.
                ForEach(starts) { entry in
                    let t = range.lowerBound + entry.start.timeIntervalSince(start)
                    let current = entry.start <= wall(shown) && entry.end > wall(shown)
                    Text(verbatim: entry.title)
                        .font(.caption2.weight(current ? .semibold : .regular))
                        .foregroundStyle(current ? .secondary : .tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: max(0, width - x(t) - 4), alignment: .leading)
                        .offset(x: x(t) + 4, y: 0)
                }
                // Track: buffered (translucent), played (solid).
                Capsule().fill(.quaternary).frame(height: 6).offset(y: 18)
                Capsule().fill(.secondary.opacity(0.5)).frame(width: width, height: 6).offset(y: 18)
                Capsule().fill(.primary).frame(width: max(6, x(shown)), height: 6).offset(y: 18)
                ForEach(starts) { entry in
                    let t = range.lowerBound + entry.start.timeIntervalSince(start)
                    Rectangle().fill(.background).frame(width: 2, height: 12).offset(x: x(t) - 1, y: 15)
                }
                Circle()
                    .fill(Theme.record)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .offset(x: width - 4, y: 17)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .frame(width: 14, height: 14)
                    .offset(x: x(shown) - 7, y: 14)
                // Clock times below.
                ForEach(ticks(from: start, to: end), id: \.self) { tick in
                    let t = range.lowerBound + tick.timeIntervalSince(start)
                    Text(tick.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .frame(width: 60)
                        .offset(x: x(t) - 30, y: 30)
                        .opacity(x(t) < 70 || x(t) > width - 50 ? 0 : 1)
                }
                Text(bufferLabel(span))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .offset(x: 2, y: 30)
                Text(end.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: width, alignment: .trailing)
                    .offset(y: 30)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if scrubbing == nil { onDragging(true) }
                        let fraction = min(max(0, value.location.x / max(width, 1)), 1)
                        scrubbing = range.lowerBound + Double(fraction) * span
                        onActivity()
                    }
                    .onEnded { _ in
                        if let target = scrubbing {
                            if target >= range.upperBound - 1 { onGoLive() } else { onSeek(target) }
                        }
                        scrubbing = nil
                        onDragging(false)
                        onActivity()
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Zeitleiste")
        .accessibilityValue(wall(shown).formatted(date: .omitted, time: .standard))
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? 10 : -10
            let target = shown + step
            if target >= range.upperBound - 1 { onGoLive() } else { onSeek(max(range.lowerBound, target)) }
        }
    }

    /// Half-hour marks inside the range.
    private func ticks(from start: Date, to end: Date) -> [Date] {
        let half: TimeInterval = 1800
        var t = Date(timeIntervalSince1970: (start.timeIntervalSince1970 / half).rounded(.up) * half)
        var result: [Date] = []
        while t < end && result.count < 12 {
            result.append(t)
            t = t.addingTimeInterval(half)
        }
        return result
    }

    private func bufferLabel(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            let hours = Double(minutes) / 60
            return String(localized: "Puffer \(hours.formatted(.number.precision(.fractionLength(0...1)))) Std.")
        }
        return String(localized: "Puffer \(max(1, minutes)) Min.")
    }
}

/// A film's timeline: elapsed, the bar (played and buffered) with a time mark under the
/// pointer, remaining.
struct FilmTimeline: View {
    @ObservedObject var progress: PlaybackProgress
    let onSeek: (Double) -> Void
    var onDragging: (Bool) -> Void = { _ in }
    var onActivity: () -> Void = {}

    @State private var scrubbing: Double?
    @State private var hover: CGFloat?

    var body: some View {
        let duration = max(progress.duration, 1)
        let shown = scrubbing ?? progress.position
        HStack(spacing: 14) {
            Text(formatTime(shown)).monospacedDigit().frame(width: 58, alignment: .leading)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 6)
                    Capsule().fill(.secondary.opacity(0.5)).frame(width: width * min(1, progress.buffered / duration), height: 6)
                    Capsule().fill(.primary).frame(width: max(6, width * min(1, shown / duration)), height: 6)
                    if let hover {
                        Rectangle().fill(.secondary).frame(width: 2, height: 12).offset(x: hover - 1)
                        Text(formatTime(Double(hover / max(width, 1)) * duration))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .fixedSize()
                            .offset(x: min(max(0, hover - 30), width - 60), y: -24)
                    }
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .frame(width: 14, height: 14)
                        .offset(x: width * min(1, shown / duration) - 7)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hover = min(max(0, point.x), width); onActivity()
                    case .ended: hover = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if scrubbing == nil { onDragging(true) }
                            scrubbing = Double(min(max(0, value.location.x / max(width, 1)), 1)) * duration
                            onActivity()
                        }
                        .onEnded { _ in
                            if let target = scrubbing { onSeek(target) }
                            scrubbing = nil
                            onDragging(false)
                            onActivity()
                        }
                )
            }
            .frame(height: 20)
            Text("−" + formatTime(max(0, duration - shown)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement()
        .accessibilityLabel("Zeitleiste")
        .accessibilityValue(formatTime(shown))
        .accessibilityAdjustableAction { direction in
            onSeek(max(0, min(duration, shown + (direction == .increment ? 10 : -10))))
        }
    }
}
