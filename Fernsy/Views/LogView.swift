import AppKit
import FernsyCore
import SwiftUI
import UniformTypeIdentifiers

/// The entries the log window shows: this run (taken from AppLog at most four times a
/// second, so bursts on background threads do not flood the main thread) or the previous one.
@MainActor
final class LogModel: ObservableObject {
    enum Run: Hashable { case current, previous }

    @Published var run: Run = .current { didSet { if run != oldValue { reload() } } }
    @Published private(set) var entries: [LogEntry] = []
    private var lastID: Int?
    private var timer: Timer?

    func start() {
        reload()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        AppLog.shared.clear()
        if run == .current { entries = [] }
    }

    private func reload() {
        switch run {
        case .current:
            entries = AppLog.shared.entries(after: nil)
            lastID = entries.last?.id
        case .previous:
            entries = AppLog.shared.previousRun()
        }
    }

    private func pull() {
        guard run == .current else { return }
        let new = AppLog.shared.entries(after: lastID)
        guard let last = new.last else { return }
        lastID = last.id
        entries.append(contentsOf: new)
        if entries.count > AppLog.capacity { entries.removeFirst(entries.count - AppLog.capacity) }
    }
}

/// Window › Log: the app's event log, for finding out what went wrong and sending it along
/// with a support request.
struct LogView: View {
    @StateObject private var model = LogModel()
    @State private var minimumLevel: LogLevel = .info
    @State private var category: LogCategory?
    @State private var search = ""
    @State private var selection = Set<LogEntry.ID>()
    @State private var follows = true

    private var shown: [LogEntry] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return model.entries.filter { entry in
            entry.level >= minimumLevel && (category == nil || entry.category == category)
                && (needle.isEmpty || entry.message.localizedCaseInsensitiveContains(needle))
        }
    }

    var body: some View {
        let shown = shown
        ScrollViewReader { proxy in
            List(shown, selection: $selection) { entry in
                LogRow(entry: entry).id(entry.id)
            }
            .listStyle(.plain)
            .font(.system(.callout, design: .monospaced))
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView("No Entries", systemImage: "list.bullet.rectangle",
                                           description: Text(model.entries.isEmpty ? "The log is empty." : "No entry matches the filter."))
                }
            }
            .onChange(of: shown.last?.id) { _, last in
                guard follows, model.run == .current, let last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
            .onAppear {
                if let last = shown.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Log")
        .toolbar { toolbar(shown) }
        .navigationTitle(model.run == .current ? "Log" : "Log (Previous Launch)")
        .onAppear {
            model.start()
            #if DEBUG
            if ProcessInfo.processInfo.environment["IPTV_TESTLOG"] == "previous" { model.run = .previous }
            #endif
        }
        .onDisappear { model.stop() }
        .onCopyCommand { [NSItemProvider(object: text(of: selected(in: shown)) as NSString)] }
        .frame(minWidth: 640, minHeight: 320)
    }

    @ToolbarContentBuilder
    private func toolbar(_ shown: [LogEntry]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("Launch", selection: $model.run) {
                Text("Current Launch").tag(LogModel.Run.current)
                Text("Previous Launch").tag(LogModel.Run.previous)
            }
            .pickerStyle(.segmented)
            .help("Show the entries of this or the previous launch")
        }
        ToolbarItemGroup {
            Picker("Level", selection: $minimumLevel) {
                Text("Errors Only").tag(LogLevel.error)
                Text("Warnings").tag(LogLevel.warning)
                Text("Info").tag(LogLevel.info)
                Text("All (with Details)").tag(LogLevel.detail)
            }
            .help("Minimum level of the shown entries")
            Picker("Area", selection: $category) {
                Text("All Areas").tag(LogCategory?.none)
                Divider()
                ForEach(LogCategory.allCases, id: \.self) { category in
                    Text(category.title).tag(LogCategory?.some(category))
                }
            }
            .help("Only show entries of one area")
            Toggle("Follow", systemImage: "arrow.down.to.line", isOn: $follows)
                .help("Show new entries automatically")
            Button("Copy", systemImage: "doc.on.doc") { copy(selected(in: shown)) }
                .help("Copy the selected entries, or all shown entries without a selection")
            Button("Save…", systemImage: "square.and.arrow.down") { save(selected(in: shown)) }
                .help("Save the selected or all shown entries as a text file")
            Button("Clear", systemImage: "trash") { model.clear(); selection = [] }
                .disabled(model.run != .current)
                .help("Clear the log of this launch")
        }
    }

    /// The selected entries, or all shown ones without a selection.
    private func selected(in shown: [LogEntry]) -> [LogEntry] {
        selection.isEmpty ? shown : shown.filter { selection.contains($0.id) }
    }

    private func text(of entries: [LogEntry]) -> String {
        entries.map(\.line).joined(separator: "\n") + "\n"
    }

    private func copy(_ entries: [LogEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text(of: entries), forType: .string)
    }

    private func save(_ entries: [LogEntry]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = String(localized: "Fernsy Log") + " " + Date().formatted(.iso8601.year().month().day()) + ".txt"
        let content = text(of: entries)
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Prompt.inform(title: String(localized: "Saving Failed"), message: error.localizedDescription)
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) } else { completion(panel.runModal()) }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).secondFraction(.fractional(3))))
                .foregroundStyle(.secondary)
            Image(systemName: entry.level.symbol)
                .foregroundStyle(entry.level.color)
                .frame(width: 16)
                .help(entry.level.title)
            Text(entry.category.title)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)
            Text(entry.message)
                .foregroundStyle(entry.level == .detail ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}

extension LogLevel {
    var title: String {
        switch self {
        case .detail: String(localized: "Detail")
        case .info: String(localized: "Info")
        case .warning: String(localized: "Warning")
        case .error: String(localized: "Error")
        }
    }

    var symbol: String {
        switch self {
        case .detail: "circle.dotted"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .detail: .secondary
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

extension LogCategory {
    var title: String {
        switch self {
        case .app: String(localized: "App")
        case .player: String(localized: "Player")
        case .network: String(localized: "Network")
        case .tuner: String(localized: "Tuner")
        case .timeshift: String(localized: "Timeshift")
        case .recordings: String(localized: "Recordings")
        case .catalog: String(localized: "Catalog")
        case .guide: String(localized: "Guide")
        case .jellyfin: String(localized: "Jellyfin")
        case .pip: String(localized: "Picture in Picture")
        case .mcp: String(localized: "Assistants")
        }
    }
}

/// Window › Log (⌥⌘L).
struct LogCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Log") { openWindow(id: "log") }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
        }
    }
}
