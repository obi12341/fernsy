import FernsyCore
import FernsyPlayer
import StoreKit
import SwiftUI

/// Recordings on iPhone and iPad (add-recording-cloud): the Mac's recordings in Fernsy Cloud,
/// newest first, streamed and deletable. Shown only with an active subscription (or one in its
/// grace period), without any prompt (cloud-account-from-icloud-key).
struct CloudRecordingsView: View {
    @EnvironmentObject private var model: TVModel
    @State private var deleting: CloudRecordingItem?

    var body: some View {
        let cloud = model.cloud
        List {
            if !cloud.hasAccount {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(verbatim: cloud.missingKeyText)
                        Button("Restore Purchases") { Task { await cloud.restore() } }
                    }
                    .padding(.vertical, 6)
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
                if cloud.items.isEmpty, cloud.phase != .loading {
                    Section {
                        Text("No recordings in Fernsy Cloud yet. Turn on uploading in Fernsy’s settings on your Mac.")
                            .foregroundStyle(TVTheme.secondary)
                    }
                }
                Section {
                    ForEach(cloud.items) { item in
                        Button { if item.meta != nil { model.play(.cloud(item)) } } label: { CloudRecordingRow(item: item) }
                            .accessibilityIdentifier("cloud.recording.\(item.id)")
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
                            }
                            .contextMenu {
                                Button("Delete from Fernsy Cloud", systemImage: "trash", role: .destructive) { deleting = item }
                            }
                    }
                }
            }
            if case .failed(let message) = cloud.phase {
                Section { Text(verbatim: message).foregroundStyle(TVTheme.warning) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Recordings")
        .refreshable { await cloud.refresh() }
        .task { await cloud.refresh() }
        .accessibilityIdentifier("cloud.recordings")
        .confirmationDialog("Delete from Fernsy Cloud?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { item in
            Button("Delete", role: .destructive) { Task { try? await cloud.delete(item) } }
        } message: { item in
            Text("“\(item.meta?.title ?? "")” is removed from Fernsy Cloud on all devices.")
        }
    }
}

private struct CloudRecordingRow: View {
    @EnvironmentObject private var model: TVModel
    let item: CloudRecordingItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.meta == nil ? "lock.icloud" : "icloud")
                .font(.title3).foregroundStyle(TVTheme.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.meta?.title ?? String(localized: "Locked cloud recording")).font(.headline).lineLimit(1)
                if let meta = item.meta {
                    Text(verbatim: "\(meta.channel) · \(meta.recordStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) · \(Duration.seconds(meta.duration).formatted(.time(pattern: .hourMinute)))")
                        .font(.subheadline).foregroundStyle(TVTheme.secondary).lineLimit(1)
                } else {
                    Text(item.isDamaged ? "Damaged" : "Key missing on this device").font(.subheadline).foregroundStyle(TVTheme.secondary)
                }
                let share = model.watchedShare(item)
                if share > 0 {
                    ProgressView(value: share).tint(.white).frame(maxWidth: 200)
                }
            }
            Spacer()
            if item.meta != nil { Image(systemName: "play.fill").foregroundStyle(TVTheme.secondary) }
        }
        .foregroundStyle(TVTheme.text)
        .contentShape(Rectangle())
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
