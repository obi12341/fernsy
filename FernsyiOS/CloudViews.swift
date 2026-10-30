import FernsyCore
import FernsyPlayer
import StoreKit
import SwiftUI

/// Recordings on iPhone and iPad (add-recording-cloud): the Mac's recordings in Fernsy Cloud,
/// newest first, streamed and deletable, without any prompt (cloud-account-from-icloud-key).
/// Recordings can be downloaded and then play from the device, also offline and after the
/// subscription ended (offline-recording-downloads).
struct CloudRecordingsView: View {
    @EnvironmentObject private var model: TVModel
    @State private var deleting: CloudRecordingItem?
    @State private var problem: String?

    /// No connection: only downloads can be listed and played.
    private var isOffline: Bool { model.signIn == .offline || !model.isNetworkAvailable }

    /// The cloud's list, plus downloads it does not show (offline, or the cloud copy is gone).
    private var rows: [CloudRecordingItem] {
        let cloud = model.cloud.items
        let ids = Set(cloud.map(\.id))
        let local = (model.downloads?.items ?? []).filter { !ids.contains($0.id) }
        return (cloud + local).sorted { $0.sortDate > $1.sortDate }
    }

    var body: some View {
        let cloud = model.cloud
        let rows = rows
        List {
            if isOffline {
                Section {
                    Label("Offline – only downloaded recordings", systemImage: "wifi.slash")
                        .foregroundStyle(TVTheme.secondary)
                        .accessibilityIdentifier("cloud.offline")
                }
            } else if !cloud.hasAccount {
                if rows.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(verbatim: cloud.missingKeyText)
                            Button("Restore Purchases") { Task { await cloud.restore() } }
                        }
                        .padding(.vertical, 6)
                    }
                }
            } else {
                if let note = cloud.deletionNote {
                    Section { Text(verbatim: note).foregroundStyle(TVTheme.warning) }
                }
                if !cloud.hasKey && !cloud.items.isEmpty {
                    Section {
                        Text("This device does not have the key for your cloud recordings yet. It comes from iCloud of the same Apple ID as on your Mac.")
                            .foregroundStyle(TVTheme.warning)
                    }
                }
                if rows.isEmpty, cloud.phase != .loading {
                    Section {
                        Text("No recordings in Fernsy Cloud yet. Turn on uploading in Fernsy’s settings on your Mac.")
                            .foregroundStyle(TVTheme.secondary)
                    }
                }
            }
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { item in
                        row(item)
                    }
                }
            }
            if !isOffline, case .failed(let message) = cloud.phase {
                Section { Text(verbatim: message).foregroundStyle(TVTheme.warning) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Recordings")
        .refreshable { await cloud.refresh() }
        .task {
            await model.downloads?.loadItems()
            if !isOffline { await cloud.refresh() }
        }
        .accessibilityIdentifier("cloud.recordings")
        .confirmationDialog("Delete from Fernsy Cloud?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { item in
            Button("Delete", role: .destructive) { Task { try? await cloud.delete(item) } }
        } message: { item in
            Text("“\(item.meta?.title ?? "")” is removed from Fernsy Cloud on all devices.")
        }
        .alert("Download not possible", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: problem ?? "")
        }
    }

    private func row(_ item: CloudRecordingItem) -> some View {
        let download = model.downloads?.download(for: item.id)
        let inCloud = model.cloud.items.contains { $0.id == item.id }
        let canDownload = item.meta != nil && inCloud && download == nil && !isOffline
        let canPlay = item.meta != nil && (download?.state == .downloaded || (!isOffline && inCloud))
        return HStack(spacing: 10) {
            Button { if canPlay { model.play(.cloud(item)) } } label: { CloudRecordingRow(item: item, download: download, canPlay: canPlay) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cloud.recording.\(item.id)")
            if canDownload {
                Button("Download", systemImage: "arrow.down.circle") { startDownload(item) }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("cloud.download.\(item.id)")
            } else if let download, download.state == .waiting || download.state == .downloading {
                Button("Cancel Download", systemImage: "xmark.circle") { model.downloads?.remove(item.id) }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("cloud.cancelDownload.\(item.id)")
            }
        }
        .swipeActions {
            if inCloud && !isOffline {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
            }
            if download != nil {
                Button("Remove Download", systemImage: "minus.circle") { model.downloads?.remove(item.id) }
            }
        }
        .contextMenu {
            if canDownload {
                Button("Download", systemImage: "arrow.down.circle") { startDownload(item) }
            }
            if let download {
                if download.state == .failed {
                    Button("Retry Download", systemImage: "arrow.clockwise") { Task { await model.downloads?.resume() } }
                }
                Button(download.state == .downloaded ? "Remove Download" : "Cancel Download", systemImage: "minus.circle") {
                    model.downloads?.remove(item.id)
                }
                .accessibilityIdentifier("cloud.removeDownload.\(item.id)")
            }
            if inCloud && !isOffline {
                Button("Delete from Fernsy Cloud", systemImage: "trash", role: .destructive) { deleting = item }
            }
        }
    }

    private func startDownload(_ item: CloudRecordingItem) {
        do {
            try model.downloads?.add(item)
        } catch let lack as CloudDownloads.NotEnoughSpace {
            problem = String(localized: "Not enough space on this device: \(CloudUploadQueue.bytes(lack.needed)) needed, \(CloudUploadQueue.bytes(lack.free)) free.")
        } catch {
            problem = error.localizedDescription
        }
    }
}

private struct CloudRecordingRow: View {
    @EnvironmentObject private var model: TVModel
    let item: CloudRecordingItem
    let download: CloudDownload?
    let canPlay: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(TVTheme.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.meta?.title ?? String(localized: "Locked cloud recording")).font(.headline).lineLimit(1)
                if let meta = item.meta {
                    Text(verbatim: "\(meta.channel) · \(meta.recordStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) · \(Duration.seconds(meta.duration).formatted(.time(pattern: .hourMinute)))")
                        .font(.subheadline).foregroundStyle(TVTheme.secondary).lineLimit(1)
                } else {
                    Text(item.isDamaged ? "Damaged" : "Key missing on this device").font(.subheadline).foregroundStyle(TVTheme.secondary)
                }
                if let download { downloadLine(download) }
                let share = model.watchedShare(item)
                if share > 0 {
                    ProgressView(value: share).tint(.white).frame(maxWidth: 200)
                }
            }
            Spacer()
            if canPlay { Image(systemName: "play.fill").foregroundStyle(TVTheme.secondary) }
        }
        .foregroundStyle(TVTheme.text)
        .contentShape(Rectangle())
    }

    private var icon: String {
        if item.meta == nil { return "lock.icloud" }
        return download?.state == .downloaded ? "arrow.down.circle.fill" : "icloud"
    }

    @ViewBuilder private func downloadLine(_ download: CloudDownload) -> some View {
        switch download.state {
        case .downloaded:
            Text("Downloaded").font(.caption).foregroundStyle(TVTheme.secondary)
                .accessibilityIdentifier("cloud.downloaded.\(item.id)")
        case .waiting:
            Text("Waiting to download").font(.caption).foregroundStyle(TVTheme.secondary)
        case .downloading:
            HStack(spacing: 8) {
                ProgressView(value: download.progress).frame(maxWidth: 160)
                Text(download.progress.formatted(.percent.precision(.fractionLength(0)))).font(.caption).monospacedDigit()
            }
            .foregroundStyle(TVTheme.secondary)
            .accessibilityIdentifier("cloud.downloading.\(item.id)")
        case .failed:
            Text(verbatim: download.message ?? String(localized: "Download stopped")).font(.caption).foregroundStyle(TVTheme.warning)
        }
    }
}

/// Settings › Fernsy Cloud on iPhone and iPad: the offer (only when a Mac with Fernsy is known
/// in iCloud), otherwise a note; with a subscription the account, moving, managing and deleting.
/// No sign-in (cloud-account-from-icloud-key).
struct CloudSettingsView: View {
    @EnvironmentObject private var model: TVModel
    @State private var managing = false
    @State private var confirmDeleteAll = false

    var body: some View {
        let cloud = model.cloud
        Form {
            Section {
                Text("Your Mac’s recordings in your own private storage, played here – end-to-end encrypted, so nobody else can see them, not even mobilistics.")
            }
            if !cloud.canUseCloud {
                Section {
                    if cloud.mayOffer {
                        if let offer = cloud.offer {
                            Text(verbatim: "\(offer.name) · \(offer.price)").font(.headline)
                        }
                        Button("Subscribe") { Task { await cloud.purchase() } }
                            .disabled(cloud.isPurchasing)
                            .accessibilityIdentifier("cloud.subscribe")
                    } else if cloud.macPresence == .unavailable {
                        Text("Fernsy Cloud needs iCloud. Sign in to iCloud with the same Apple ID as on your Mac.")
                            .foregroundStyle(TVTheme.secondary)
                    } else if cloud.macPresence == .unknown {
                        Text("Fernsy on your Mac records, and Fernsy Cloud brings the recordings here. Install Fernsy on a Mac with the same Apple ID to use it.")
                            .foregroundStyle(TVTheme.secondary)
                            .accessibilityIdentifier("cloud.needsMac")
                    }
                    Button("Restore Purchases") { Task { await cloud.restore() } }
                        .disabled(cloud.isPurchasing)
                }
            } else {
                if let account = cloud.account, cloud.hasAccount {
                    Section {
                        LabeledContent("Subscription", value: CloudModel.stateText(account))
                        LabeledContent("Storage", value: CloudModel.storageText(account))
                        if let note = cloud.deletionNote { Text(verbatim: note).foregroundStyle(TVTheme.warning) }
                    } footer: {
                        Text("Only your devices with the same Apple ID can play your cloud recordings, because the key stays in your iCloud.")
                    }
                }
                if cloud.canMoveSubscription {
                    Section {
                        Text("Your subscription is linked to another Fernsy Cloud key, for example from before your iCloud data was reset. Move it here to use Fernsy Cloud with this key. Recordings under the old key cannot be read anymore and are deleted after 30 days.")
                        Button("Move Subscription Here") { Task { await cloud.moveSubscription() } }
                            .accessibilityIdentifier("cloud.move")
                    }
                }
                Section {
                    Button("Manage Subscription") { managing = true }
                    if cloud.hasAccount {
                        Button("Delete Fernsy Cloud Data", role: .destructive) { confirmDeleteAll = true }
                            .accessibilityIdentifier("cloud.deleteAll")
                    }
                }
            }
            // Also without a subscription: downloads stay (offline-recording-downloads).
            if let downloads = model.downloads, !downloads.downloads.isEmpty {
                Section {
                    LabeledContent("Downloads", value: CloudUploadQueue.bytes(downloads.usedBytes))
                        .accessibilityIdentifier("cloud.downloadsStorage")
                } footer: {
                    Text("Downloaded recordings stay on this device and play without a connection, also after the subscription ends.")
                }
            }
            if case .failed(let message) = cloud.phase {
                Section { Text(verbatim: message).foregroundStyle(TVTheme.warning) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "Fernsy Cloud"))
        .manageSubscriptionsSheet(isPresented: $managing)
        .confirmationDialog("Delete all Fernsy Cloud data?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { Task { try? await cloud.deleteCloudData() } }
        } message: {
            Text("All cloud recordings are removed on all devices. Recordings on your Mac stay. Your subscription continues until you cancel it under Manage Subscription.")
        }
        .task {
            await cloud.refreshMacPresence()
            await cloud.refreshSubscription()
            await cloud.refresh()
        }
    }
}
