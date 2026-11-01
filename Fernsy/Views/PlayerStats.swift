import Charts
import FernsyCore
import FernsyPlayer
import SwiftUI

struct AudioStatusBadge: View {
    let text: String
    let waiting: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.slash.fill")
            Text(text)
            if waiting {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            .environment(\.colorScheme, .dark)
            .help(waiting ? String(localized: "The channel is currently sending no audio. Sound will resume automatically.")
                          : String(localized: "This channel has no audio track."))
    }
}

struct StatsOverlay: View {
    let stats: PlaybackStats
    let status: PlayerEngine.Status
    @ObservedObject var history: BufferHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            grid
            BufferChart(history: history, isTimeshift: stats.timeshiftAhead != nil)
        }
        // Size to the content instead of stretching (the divider would take the full width).
        .fixedSize()
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The rows shared with the Apple TV (FernsyCore `StreamInfo`).
    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(StreamInfo.rows(stats, averageMbps: history.averageMbps), id: \.label) { row in
                if row.startsSection { Divider().overlay(.white.opacity(0.25)).gridCellColumns(2) }
                GridRow {
                    Text(verbatim: row.label).foregroundStyle(.white.opacity(0.6))
                    Text(verbatim: row.value)
                }
            }
        }
    }
}

/// Buffer over the last two minutes: player and network share stacked, the reconnect
/// threshold dashed, and reconnects, restarts and stalls marked.
struct BufferChart: View {
    @ObservedObject var history: BufferHistory
    /// The second share is what the timeshift buffer holds ahead, not network bytes.
    var isTimeshift = false
    /// Timeshifted playback can have hours ahead; the chart is about the last seconds.
    private static let cap = 60.0

    private static let playerColor = Color(red: 0.35, green: 0.62, blue: 1.0)
    private static let networkColor = Color(red: 0.55, green: 0.85, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Buffer, last 2 min").foregroundStyle(.white.opacity(0.6))
                Spacer()
                legend(Self.playerColor, "Player")
                legend(Self.networkColor, isTimeshift ? "Disk" : "Net")
            }
            chart.frame(width: 300, height: 90)
            HStack(spacing: 10) {
                legend(.orange, "Reconnect")
                legend(.purple, "Restart")
                legend(.red, "Rebuffer")
                Spacer()
            }
            .font(.system(size: 9, design: .monospaced))
        }
        .frame(width: 300)
    }

    private var chart: some View {
        let now = history.samples.last?.time ?? Date()
        let samples = history.samples
        let peak = min(Self.cap, samples.map { $0.player + $0.network }.max() ?? 0)
        return Chart {
            ForEach(samples) { sample in
                let x = sample.time.timeIntervalSince(now)
                AreaMark(x: .value("Time", x), y: .value("Seconds", sample.player), stacking: .standard)
                    .foregroundStyle(by: .value("Share", "Player"))
                AreaMark(x: .value("Time", x), y: .value("Seconds", min(sample.network, max(0, Self.cap - sample.player))), stacking: .standard)
                    .foregroundStyle(by: .value("Share", "Net"))
                ForEach(Array(sample.events.enumerated()), id: \.offset) { _, event in
                    RuleMark(x: .value("Time", x))
                        .foregroundStyle(Self.color(for: event))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            RuleMark(y: .value("Threshold", 4))
                .foregroundStyle(.white.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartForegroundStyleScale(["Player": Self.playerColor.opacity(0.8), "Net": Self.networkColor.opacity(0.7)])
        .chartLegend(.hidden)
        .chartXScale(domain: -BufferHistory.window...0)
        .chartYScale(domain: 0...max(10, (peak / 5).rounded(.up) * 5))
        .chartXAxis {
            AxisMarks(values: [-120, -90, -60, -30, 0]) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(seconds == 0 ? "now" : "\(Int(seconds)) s")
                    }
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) { Text("\(Int(seconds)) s") }
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 9, design: .monospaced))
    }

    private static func color(for event: BufferHistory.Event) -> Color {
        switch event {
        case .reconnect: return .orange
        case .restart: return .purple
        case .rebuffer: return .red
        }
    }

    private func legend(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.white.opacity(0.7))
        }
    }
}
