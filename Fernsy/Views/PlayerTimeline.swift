import FernsyCore
import FernsyPlayer
import SwiftUI

/// The timelines' bar and knob are the system slider (as the volume). It runs the knob's centre
/// inside its track with an inset of half the knob; text placed beside it uses the same mapping
/// (measured with IPTV_TESTTIMELINE, see the system-slider-timeline design).
enum TimelineSlider {
    static let controlSize = ControlSize.small
    static let knobInset: CGFloat = 5.25
    /// The played part, as before the system slider (not the accent colour).
    static let played = Color.primary

    /// x of a fraction of the range in a slider of `width`.
    static func x(_ fraction: Double, width: CGFloat) -> CGFloat {
        knobInset + CGFloat(min(max(fraction, 0), 1)) * max(0, width - 2 * knobInset)
    }
}

/// Live TV's timeline over the timeshift buffer: clock times below, the shows' starts and
/// titles above, a red dot at the live end. Dragging or clicking seeks; letting go at the
/// end returns to live.
struct LiveTimeline: View {
    @ObservedObject var progress: PlaybackProgress
    /// Playable buffer time range (oldest second … live edge).
    let range: ClosedRange<Double>
    let entries: [EPGEntry]
    /// Clock time of a buffer time, read from the buffer (nil when it has none).
    var wallTime: (Double) -> Date? = { _ in nil }
    let onSeek: (Double) -> Void
    let onGoLive: () -> Void
    var onDragging: (Bool) -> Void = { _ in }
    var onActivity: () -> Void = {}

    @State private var scrubbing: Double?

    private var shown: Double {
        if let scrubbing { return scrubbing }
        return progress.followsLive ? range.upperBound : min(max(progress.position, range.lowerBound), range.upperBound)
    }

    /// Clock time of a buffer time. The buffer's own mapping follows a seek at once; the
    /// published `wallClock` only with the next position update.
    private func wall(_ t: Double) -> Date {
        wallTime(t) ?? (progress.wallClock ?? Date()).addingTimeInterval(t - progress.position)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = max(1, range.upperBound - range.lowerBound)
            let start = wall(range.lowerBound), end = wall(range.upperBound)
            let clockSpan = max(1, end.timeIntervalSince(start))
            // Buffer time of a clock time, between the range's ends.
            let time = { (date: Date) -> Double in range.lowerBound + date.timeIntervalSince(start) / clockSpan * span }
            let x = { (t: Double) -> CGFloat in TimelineSlider.x((t - range.lowerBound) / span, width: width) }
            let starts = entries.filter { $0.start > start && $0.start < end }
            let current = wall(shown)
            VStack(alignment: .leading, spacing: 0) {
                // Show titles above, at their start.
                ZStack(alignment: .topLeading) {
                    ForEach(starts) { entry in
                        let at = x(time(entry.start))
                        let isCurrent = entry.start <= current && entry.end > current
                        Text(verbatim: entry.title)
                            .font(.caption2.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? .secondary : .tertiary)
                            .lineLimit(1)
                            .frame(maxWidth: max(0, width - at - 4), alignment: .leading)
                            .offset(x: at + 4)
                    }
                }
                .frame(width: width, height: 14, alignment: .topLeading)
                .allowsHitTesting(false)
                Slider(value: Binding(get: { shown }, set: { scrubbing = $0; onActivity() }), in: range) {
                    Text("Timeline")
                } ticks: {
                    SliderTickContentForEach(starts.map { time($0.start) }, id: \.self) { SliderTick($0) }
                } onEditingChanged: { editing in
                    if editing {
                        onDragging(true)
                    } else {
                        if let target = scrubbing {
                            if target >= range.upperBound - 1 { onGoLive() } else { onSeek(target) }
                        }
                        scrubbing = nil
                        onDragging(false)
                    }
                    onActivity()
                }
                .labelsHidden()
                .controlSize(TimelineSlider.controlSize)
                .tint(TimelineSlider.played)
                #if DEBUG
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { TimelineTestDrag.sliderFrame = $0 }
                #endif
                .background(alignment: .leading) {
                    Circle()
                        .fill(Theme.record)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                        .offset(x: x(range.upperBound) - 4)
                }
                // Clock times below.
                ZStack(alignment: .topLeading) {
                    ForEach(ticks(from: start, to: end), id: \.self) { tick in
                        let at = x(time(tick))
                        Text(tick.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .frame(width: 60)
                            .offset(x: at - 30)
                            .opacity(at < 70 || at > width - 50 ? 0 : 1)
                    }
                    Text(bufferLabel(span))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .offset(x: 2)
                    Text(end.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: width, alignment: .trailing)
                }
                .frame(width: width, height: 14, alignment: .topLeading)
                .allowsHitTesting(false)
            }
        }
        .frame(height: 48)
        // One element for VoiceOver: the slider's own steps would only move the knob.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline")
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
            return String(localized: "Buffer \(hours.formatted(.number.precision(.fractionLength(0...1)))) h")
        }
        return String(localized: "Buffer \(max(1, minutes)) min")
    }
}

/// A film's timeline: elapsed, the bar with a time mark under the pointer, remaining.
struct FilmTimeline: View {
    @ObservedObject var progress: PlaybackProgress
    let onSeek: (Double) -> Void
    var onDragging: (Bool) -> Void = { _ in }
    var onActivity: () -> Void = {}

    @State private var scrubbing: Double?
    @State private var hover: CGFloat?

    var body: some View {
        let duration = max(progress.duration, 1)
        let shown = min(scrubbing ?? progress.position, duration)
        HStack(spacing: 14) {
            Text(formatTime(shown)).monospacedDigit().frame(width: 58, alignment: .leading)
            Slider(value: Binding(get: { shown }, set: { scrubbing = $0; onActivity() }), in: 0...duration) {
                Text("Timeline")
            } onEditingChanged: { editing in
                if editing {
                    onDragging(true)
                } else {
                    if let target = scrubbing { onSeek(target) }
                    scrubbing = nil
                    onDragging(false)
                }
                onActivity()
            }
            .labelsHidden()
            .controlSize(TimelineSlider.controlSize)
            .tint(TimelineSlider.played)
            #if DEBUG
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { TimelineTestDrag.sliderFrame = $0 }
            #endif
            .overlay(alignment: .leading) {
                // The time a click would seek to, at the pointer.
                GeometryReader { geo in
                    let width = geo.size.width
                    if let hover {
                        let fraction = Double((hover - TimelineSlider.knobInset) / max(1, width - 2 * TimelineSlider.knobInset))
                        Text(formatTime(min(max(fraction, 0), 1) * duration))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .fixedSize()
                            .offset(x: min(max(0, hover - 30), width - 60), y: -26)
                    }
                }
                .allowsHitTesting(false)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hover = point.x; onActivity()
                case .ended: hover = nil
                }
            }
            Text("−" + formatTime(max(0, duration - shown)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline")
        .accessibilityValue(formatTime(shown))
        .accessibilityAdjustableAction { direction in
            onSeek(max(0, min(duration, shown + (direction == .increment ? 10 : -10))))
        }
    }
}

#if DEBUG
/// IPTV_TESTTIMELINE=<inset>: system sliders at several widths and sizes on the player's panel
/// material, with a red 1 pt mark at `inset + fraction · (width − 2 · inset)` for the knob's
/// value and green marks under the ticks, so window screenshots show whether text placed by
/// that mapping lines up with the knob and the ticks.
struct TimelineAlignmentTestView: View {
    let inset: CGFloat
    private let ticks: [Double] = [0.25, 0.5, 0.75]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 0.75), Color(red: 0.12, green: 0.18, blue: 0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 18) {
                ForEach([CGFloat(300), 600, 1100], id: \.self) { width in
                    ForEach([ControlSize.mini, .small], id: \.self) { size in
                        ForEach([0.0, 0.5, 1.0], id: \.self) { value in
                            row(width: width, size: size, value: value)
                        }
                    }
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(30)
        }
    }

    private func x(_ fraction: Double, _ width: CGFloat) -> CGFloat {
        inset + CGFloat(fraction) * (width - 2 * inset)
    }

    private func row(width: CGFloat, size: ControlSize, value: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Slider(value: .constant(value), in: 0...1) {
                EmptyView()
            } ticks: {
                SliderTickContentForEach(ticks, id: \.self) { SliderTick($0) }
            }
            .labelsHidden()
            .controlSize(size)
            .frame(width: width)
            Rectangle().fill(.red).frame(width: 1, height: 6).offset(x: x(value, width) - 0.5, y: -8)
            ForEach(ticks, id: \.self) { tick in
                Rectangle().fill(.green).frame(width: 1, height: 6).offset(x: x(tick, width) - 0.5, y: -8)
            }
        }
        .frame(width: width, alignment: .leading)
        .padding(.top, 8)
        .border(.yellow.opacity(0.6), width: 0.5)
    }
}
#endif

#if DEBUG
/// IPTV_TESTDRAG=<at s>:<to fraction>[:<hold s>],…: shows the controls, presses the mouse on
/// the timeline's knob, drags it to that fraction of the bar within a second, holds, releases,
/// then moves the pointer to 0.6 of the bar (film hover mark). The events go into the app's own
/// queue (the slider tracks the mouse in its own loop); nothing reaches the system and the
/// pointer does not move.
enum TimelineTestDrag {
    /// The visible timeline slider, in window coordinates (top left origin).
    static var sliderFrame: CGRect?

    static func run(spec: String, window: @escaping () -> NSWindow?, knob: @escaping () -> Double,
                    onStart: @escaping () -> Void, onReleased: @escaping () -> Void) {
        for drag in spec.split(separator: ",") {
            schedule(String(drag), window: window, knob: knob, onStart: onStart, onReleased: onReleased)
        }
    }

    private static func schedule(_ spec: String, window: @escaping () -> NSWindow?, knob: @escaping () -> Double,
                                 onStart: @escaping () -> Void, onReleased: @escaping () -> Void) {
        let p = spec.split(separator: ":").compactMap { Double($0) }
        guard p.count >= 2 else { return }
        let hold = p.count > 2 ? p[2] : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + p[0] - 0.5) { onStart() }
        DispatchQueue.main.asyncAfter(deadline: .now() + p[0]) {
            guard let window = window(), let frame = sliderFrame, let height = window.contentView?.bounds.height else {
                debugLog("[test] drag: no timeline")
                return
            }
            let from = knob(), to = min(max(p[1], 0), 1)
            let point = { (f: Double) in
                NSPoint(x: frame.minX + TimelineSlider.x(f, width: frame.width), y: height - frame.midY)
            }
            debugLog("[test] drag from \(String(format: "%.3f", from)) to \(String(format: "%.3f", to)), hold \(hold) s")
            var steps: [(TimeInterval, NSEvent.EventType, NSPoint)] = [(0, .leftMouseDown, point(from))]
            for i in 1...10 { steps.append((0.1 * Double(i), .leftMouseDragged, point(from + (to - from) * Double(i) / 10))) }
            steps.append((1 + hold, .leftMouseUp, point(to)))
            steps.append((2 + hold, .mouseMoved, point(0.6)))
            for (i, step) in steps.enumerated() {
                // Common modes: the slider's tracking loop runs in the event tracking mode.
                let timer = Timer(timeInterval: step.0, repeats: false) { _ in
                    guard let event = NSEvent.mouseEvent(with: step.1, location: step.2, modifierFlags: [],
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: i,
                                                         clickCount: step.1 == .mouseMoved ? 0 : 1,
                                                         pressure: step.1 == .leftMouseDown || step.1 == .leftMouseDragged ? 1 : 0) else { return }
                    NSApp.postEvent(event, atStart: false)
                    if step.1 == .leftMouseUp {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { onReleased() }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
}
#endif
