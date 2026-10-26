import SwiftUI

/// The selected channel next to the Live TV list: what runs now (with "Record") and the
/// shows that follow, each recordable.
struct ChannelDetailPane: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    let number: Int?
    let onInfo: () -> Void
    var showInGuide: (() -> Void)?

    var body: some View {
        DetailContent(channel: channel, number: number, guide: app.epg.guide(channel.id), onInfo: onInfo, showInGuide: showInGuide)
            .task(id: channel.id) { await app.epg.load(channel.id, client: app.client) }
    }
}

private struct DetailContent: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    let number: Int?
    @ObservedObject var guide: ChannelGuide
    let onInfo: () -> Void
    let showInGuide: (() -> Void)?

    var body: some View {
        // Redrawn every full minute: current show, remaining time and the following shows
        // (with their buttons) move on while the pane stays open.
        TimelineView(LiveClock.everyMinute) { context in
            content(now: LiveClock.now(context.date))
        }
    }

    private func content(now: Date) -> some View {
        let entries = (guide.entries ?? []).filter { $0.end > now }
        let current = entries.first { $0.start <= now }
        let upcoming = Array(entries.filter { $0.start >= (current?.end ?? now) }.prefix(4))
        let offline = app.offlineChannels.contains(channel.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                if offline {
                    Label("Channel is offline at the provider", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Theme.warning)
                }
                if let current {
                    NowCard(channel: channel, entry: current, now: now)
                } else if guide.entries != nil {
                    Text("No program data").font(.callout).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
                if !upcoming.isEmpty {
                    Text("NEXT")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(upcoming) { UpcomingRow(channel: channel, entry: $0) }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            LogoTile(url: channel.icon, name: channel.displayName, width: 80)
            VStack(alignment: .leading, spacing: 4) {
                TaggedName(name: channel.parsed, font: .title3, weight: .bold)
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        let category = app.liveCategories.first { $0.id == channel.categoryId }?.displayName
        let parts = [number.map { String(localized: "No. \($0)") }, category].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                app.play(channel)
            } label: {
                Label("Watch", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                app.toggleFavorite("live:\(channel.id)")
            } label: {
                Image(systemName: app.isFavorite("live:\(channel.id)") ? "star.fill" : "star")
                    .foregroundStyle(app.isFavorite("live:\(channel.id)") ? .yellow : .primary)
            }
            .controlSize(.large)
            .help(app.isFavorite("live:\(channel.id)") ? "Remove from Favorites" : "Add to Favorites")
            Menu {
                ChannelMenu(channel: channel, onInfo: onInfo, showInGuide: showInGuide)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .controlSize(.large)
        }
    }
}

/// "JETZT": time, title, progress with remaining minutes, description and "Record".
private struct NowCard: View {
    let channel: LiveChannel
    let entry: EPGEntry
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NOW").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.tertiary)
                Spacer()
                Text("\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Text(verbatim: entry.title).font(.headline)
            HStack(spacing: 8) {
                ProgressBar(value: entry.progress(at: now), height: 4)
                Text("\(max(1, Int(entry.end.timeIntervalSince(now) / 60))) min left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if !entry.description.isEmpty {
                Text(verbatim: entry.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            RecordCapsule(channel: channel, entry: entry, large: true)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct UpcomingRow: View {
    let channel: LiveChannel
    let entry: EPGEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.start.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.title).font(.callout.weight(.semibold)).lineLimit(2)
                if !entry.description.isEmpty {
                    Text(verbatim: entry.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            RecordCapsule(channel: channel, entry: entry, large: false)
        }
    }
}

/// "● Aufnehmen" or, once planned, a filled "● Geplant" / "● Aufnahme läuft"; clicking
/// again removes the plan or stops the recording.
struct RecordCapsule: View {
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    let entry: EPGEntry
    var large = false

    var body: some View {
        let existing = recorder.recording(channelId: channel.id, entry: entry).flatMap { $0.isUpcomingOrRunning ? $0 : nil }
        let running = existing?.status == .recording
        Button {
            if let existing {
                recorder.stop(existing.id)
            } else {
                recorder.schedule(entry, on: channel).present()
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(existing == nil ? Theme.record : .white).frame(width: large ? 8 : 6, height: large ? 8 : 6)
                Text(existing == nil ? "Record" : running ? "Recording in Progress" : "Scheduled")
            }
            .font((large ? Font.callout : .caption).weight(.semibold))
            .foregroundStyle(existing == nil ? Theme.record : .white)
            .padding(.horizontal, large ? 11 : 8)
            .padding(.vertical, large ? 5 : 3)
            .background(existing == nil ? Theme.record.opacity(0.15) : Theme.record, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(existing == nil ? "Record this show (Fernsy has to be open)"
              : running ? "Stop Recording" : "Remove scheduled recording")
        .opacity(entry.end > Date() ? 1 : 0)
    }
}

/// The channel's actions, shared by the list's context menu and the pane's "⋯" menu.
struct ChannelMenu: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let channel: LiveChannel
    let onInfo: () -> Void
    var showInGuide: (() -> Void)?

    var body: some View {
        Button("Watch") { app.play(channel) }
        if let showInGuide {
            Button("Show in Guide", action: showInGuide)
        }
        Button(app.isFavorite("live:\(channel.id)") ? "Remove from Favorites" : "Add to Favorites") {
            app.toggleFavorite("live:\(channel.id)")
        }
        .keyboardShortcut("d", modifiers: .command)
        if app.recentChannels.contains(channel.id) {
            Button("Remove from Recently Watched") { app.removeRecent(channel.id) }
        }
        if let running = recorder.active(on: channel.id) {
            Divider()
            Button("Stop Recording") { recorder.stop(running.id) }
        }
        Divider()
        ChannelVisibilityButton(channel: channel)
        if let id = channel.categoryId, let category = app.liveCategories.first(where: { $0.id == id }),
           !app.isCategoryHidden(id) {
            Button("Hide Category “\(category.displayName)”") { app.setCategory(id, hidden: true) }
        }
        Divider()
        Button("Channel Info…", action: onInfo)
            .keyboardShortcut("i", modifiers: .command)
    }
}
