import FernsyCore
import SwiftUI

/// Recordings: running, scheduled and finished, filtered by the category column.
struct RecordingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let filter: String

    var body: some View {
        let all = recorder.recordings
        let running = all.filter { $0.status == .recording }
        let scheduled = all.filter { $0.status == .scheduled }.sorted { $0.start < $1.start }
        let finished = all.filter { !$0.isUpcomingOrRunning }.sorted { $0.start > $1.start }
        let showUpcoming = filter == allCategoryID || filter == "upcoming"
        let showFinished = filter == allCategoryID || filter == "done"

        Group {
            if (showUpcoming ? running.count + scheduled.count : 0) + (showFinished ? finished.count : 0) == 0 {
                ContentUnavailableView {
                    Label("No Recordings", systemImage: "record.circle")
                } description: {
                    Text("Select a show in the guide and click “Record”, or press R in the player. Recordings run while Fernsy is open.")
                }
            } else {
                List {
                    if showUpcoming && !running.isEmpty {
                        Section("Recording") { ForEach(running) { RecordingRow(recording: $0) } }
                    }
                    if showUpcoming && !scheduled.isEmpty {
                        Section("Scheduled") { ForEach(scheduled) { RecordingRow(recording: $0) } }
                    }
                    if showFinished && !finished.isEmpty {
                        Section("Recorded") { ForEach(finished) { RecordingRow(recording: $0) } }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Label("Recordings only run while Fernsy is open – also with all windows closed, via the menu bar icon.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
        }
        .navigationTitle("Recordings")
        .toolbar {
            ToolbarItem {
                Button {
                    try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Recorder.folder)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Open the recordings folder in Finder")
            }
        }
    }
}

struct RecordingRow: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let recording: Recording

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: recording.title).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(verbatim: recording.channelName)
                    Text(verbatim: "·")
                    Text(timeText).monospacedDigit()
                    if recording.padBefore > 0 || recording.padAfter > 0 {
                        Text(verbatim: "·")
                        Text("Recording \(recording.recordStart.formatted(date: .omitted, time: .shortened))–\(recording.recordEnd.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                    }
                    if let detail { Text(verbatim: "·"); Text(detail) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if let outcome {
                    Label {
                        Text(verbatim: outcome.text).lineLimit(2)
                    } icon: {
                        Image(systemName: outcome.symbol).foregroundStyle(outcome.failed ? Theme.warning : Color.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(outcome.failed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .help(outcome.text)
                }
                if let gaps = gapsNote {
                    Label {
                        Text(verbatim: gaps.text).lineLimit(1)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(gaps.help)
                }
                if recording.status == .recording {
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        ProgressBar(value: progress(at: context.date), tint: Theme.record)
                    }
                    .frame(maxWidth: 320)
                    .padding(.top, 3)
                }
            }
            Spacer()
            actions
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if canPlay { app.play(recording) } }
        .contextMenu {
            if canPlay { Button("Play") { app.play(recording) } }
            if let url = recorder.fileURL(recording), FileManager.default.fileExists(atPath: url.path) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            switch recording.status {
            case .recording: Button("Stop Recording") { recorder.stop(recording.id) }
            case .scheduled: Button("Remove Recording", role: .destructive) { recorder.stop(recording.id) }
            default: Button("Move to Trash", role: .destructive) { recorder.delete(recording.id) }
            }
        }
    }

    private var canPlay: Bool {
        guard recording.status == .recording || recording.status == .done || recording.status == .failed,
              let url = recorder.fileURL(recording) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    @ViewBuilder
    private var icon: some View {
        switch recording.status {
        case .recording: Image(systemName: "record.circle.fill").foregroundStyle(.red).symbolEffect(.pulse)
        case .scheduled: Image(systemName: "clock").foregroundStyle(.secondary)
        case .done: Image(systemName: "film").foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        case .skipped, .missed: Image(systemName: "minus.circle").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if canPlay {
                Button("Play", systemImage: "play.fill") { app.play(recording) }
                    .labelStyle(.iconOnly)
                    .help("Play")
            }
            switch recording.status {
            case .recording:
                Button("Quit", systemImage: "stop.fill") { recorder.stop(recording.id) }
                    .labelStyle(.iconOnly)
                    .help("Stop Recording")
            case .scheduled:
                Button("Remove", systemImage: "xmark") { recorder.stop(recording.id) }
                    .labelStyle(.iconOnly)
                    .help("Remove scheduled recording")
            default:
                Button("Delete", systemImage: "trash") { recorder.delete(recording.id) }
                    .labelStyle(.iconOnly)
                    .help("Move to Trash")
            }
        }
        .buttonStyle(.borderless)
    }

    private var timeText: String {
        let day = Calendar.current.isDateInToday(recording.start)
            ? String(localized: "Today")
            : recording.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) \(recording.start.formatted(date: .omitted, time: .shortened)) – \(recording.end.formatted(date: .omitted, time: .shortened))"
    }

    private var detail: String? {
        switch recording.status {
        case .recording where recording.fileName == nil: return String(localized: "Waiting for the channel…")
        case .skipped, .missed: return nil
        case .failed where recording.bytes == nil: return nil
        default: return recording.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        }
    }

    /// What went wrong, with its cause: "fehlgeschlagen · Keine Daten vom Sender".
    private var outcome: (symbol: String, text: String, failed: Bool)? {
        switch recording.status {
        case .failed:
            let cause = recording.error.map { " · \($0)" } ?? ""
            return ("exclamationmark.triangle.fill", String(localized: "failed") + cause, true)
        case .missed:
            return ("minus.circle", String(localized: "missed · Fernsy was not open"), false)
        case .skipped:
            return ("minus.circle", String(localized: "skipped"), false)
        case .done where recording.error != nil:
            return ("exclamationmark.triangle.fill", recording.error ?? "", true)
        default:
            return nil
        }
    }

    /// Content the provider did not deliver: "Lücke 21:38 (1:41) – Anbieter hat zu wenig geliefert".
    private var gapsNote: (text: String, help: String)? {
        let gaps = recording.gaps
        guard !gaps.isEmpty else { return nil }
        let cause = String(localized: "provider delivered too little")
        let single = gaps.map { String(localized: "Gap \($0.at.formatted(date: .omitted, time: .shortened)) (\(Self.duration($0.seconds)))") }
        let help = single.joined(separator: "\n") + "\n" + cause
        if gaps.count > 2 {
            let total = Self.duration(gaps.reduce(0) { $0 + $1.seconds })
            return (String(localized: "\(gaps.count) gaps, \(total) in total – \(cause)"), help)
        }
        return (single.joined(separator: ", ") + " – " + cause, help)
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func progress(at date: Date) -> Double {
        let total = recording.recordEnd.timeIntervalSince(recording.recordStart)
        guard total > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(recording.recordStart) / total))
    }
}

/// "Record" / "Remove recording" for a show, used by the guide and the channel list.
struct RecordButton: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    let entry: EPGEntry

    var body: some View {
        if entry.end > Date() {
            let existing = recorder.recording(channelId: channel.id, entry: entry).flatMap { $0.isUpcomingOrRunning ? $0 : nil }
            if let existing {
                Button(existing.status == .recording ? "Stop Recording" : "Remove Recording",
                       systemImage: existing.status == .recording ? "stop.circle" : "xmark.circle") {
                    recorder.stop(existing.id)
                }
                .help(existing.status == .recording ? "Stop Recording" : "Remove scheduled recording")
            } else {
                Button("Record", systemImage: "record.circle") {
                    recorder.schedule(entry, on: channel).present()
                }
                .help("Record this show (Fernsy has to be open)")
            }
        }
    }
}
