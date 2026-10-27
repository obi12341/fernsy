import Charts
import FernsyCore
import FernsyPlayer
import SwiftUI

/// Settings › Playback › "Technical Info" (tvos-stream-info); debug builds also turn it on with
/// `IPTV_SHOWINFO`, as on the Mac.
enum StreamInfoSetting {
    static let key = "player.showStreamInfo"

    static var forced: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["IPTV_SHOWINFO"] != nil
        #else
        false
        #endif
    }
}

/// The technical information panel of every Apple TV player: the rows the Mac's overlay shows
/// (FernsyCore `StreamInfo`) and the two-minute buffer chart, top right, never focusable.
struct StreamInfoPanel: View {
    @ObservedObject var engine: PlayerEngine
    @AppStorage(StreamInfoSetting.key) private var enabled = false

    var body: some View {
        if enabled || StreamInfoSetting.forced {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 3) {
                    ForEach(StreamInfo.rows(engine.stats, averageMbps: engine.bufferHistory.averageMbps), id: \.label) { row in
                        if row.startsSection { Rectangle().fill(.white.opacity(0.25)).frame(height: 1).gridCellColumns(2) }
                        GridRow {
                            Text(verbatim: row.label).foregroundStyle(.white.opacity(0.6))
                            Text(verbatim: row.value)
                        }
                    }
                }
                TVBufferChart(history: engine.bufferHistory, isTimeshift: engine.stats.timeshiftAhead != nil)
            }
            .fixedSize()
            .font(.system(size: 17, design: .monospaced))
            .foregroundStyle(.white)
            .padding(20)
            .background(.black.opacity(0.68), in: .rect(cornerRadius: 18))
            .padding(.trailing, 90)
            // Below the recording badge in the live player's top right corner.
            .padding(.top, 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("player.streamInfo")
        }
    }
}

/// The Mac's buffer chart at TV size: player and network (or disk) share stacked, the reconnect
/// threshold dashed, reconnects, restarts and stalls marked.
private struct TVBufferChart: View {
    @ObservedObject var history: BufferHistory
    let isTimeshift: Bool
    private static let cap = 60.0
    private static let playerColor = Color(red: 0.35, green: 0.62, blue: 1.0)
    private static let networkColor = Color(red: 0.55, green: 0.85, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text("Buffer, last 2 min").foregroundStyle(.white.opacity(0.6))
                Spacer()
                legend(Self.playerColor, "Player")
                legend(Self.networkColor, isTimeshift ? "Disk" : "Net")
            }
            chart.frame(height: 100)
            HStack(spacing: 16) {
                legend(.orange, "Reconnect")
                legend(.purple, "Restart")
                legend(.red, "Rebuffer")
            }
            .font(.system(size: 15, design: .monospaced))
        }
        .frame(width: 520)
    }

    private func legend(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 12)
            Text(title).foregroundStyle(.white.opacity(0.7))
        }
    }

    private static func color(for event: BufferHistory.Event) -> Color {
        switch event {
        case .reconnect: .orange
        case .restart: .purple
        case .rebuffer: .red
        }
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
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            RuleMark(y: .value("Threshold", 4))
                .foregroundStyle(.white.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .chartForegroundStyleScale(["Player": Self.playerColor.opacity(0.8), "Net": Self.networkColor.opacity(0.7)])
        .chartLegend(.hidden)
        .chartXScale(domain: -BufferHistory.window...0)
        .chartYScale(domain: 0...max(10, (peak / 5).rounded(.up) * 5))
        .chartXAxis {
            AxisMarks(values: [-120, -90, -60, -30, 0]) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) { Text(seconds == 0 ? "now" : "\(Int(seconds)) s").font(.system(size: 15, design: .monospaced)) }
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) { Text("\(Int(seconds)) s").font(.system(size: 15, design: .monospaced)) }
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 15, design: .monospaced))
    }
}
