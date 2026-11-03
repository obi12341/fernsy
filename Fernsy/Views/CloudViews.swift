import FernsyCore
import FernsyPlayer
import SwiftUI

/// The cloud line of a recording row (add-recording-cloud): upload progress, "in Fernsy Cloud",
/// or why an upload stopped.
struct CloudRowStatus: View {
    @EnvironmentObject private var app: AppModel
    let recording: Recording

    var body: some View {
        if let job = app.cloudUploads.job(for: recording.id) {
            HStack(spacing: 6) {
                Image(systemName: job.state == .failed ? "exclamationmark.icloud" : "icloud.and.arrow.up")
                    .foregroundStyle(job.state == .failed ? Theme.warning : Color.secondary)
                switch job.state {
                case .queued: Text("Waiting to upload")
                case .uploading: Text("Uploading \(job.progress.formatted(.percent.precision(.fractionLength(0))))")
                case .waiting, .failed: Text(verbatim: job.message ?? "")
                }
                if job.state == .uploading || job.state == .queued {
                    ProgressBar(value: job.progress, tint: .accentColor).frame(maxWidth: 160)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if app.cloudUploads.uploaded[recording.id] != nil {
            Label("In Fernsy Cloud", systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Upload, cancel and cloud-delete actions for a local recording's context menu.
struct CloudRowMenu: View {
    @EnvironmentObject private var app: AppModel
    let recording: Recording
    @Binding var confirmDelete: Bool

    var body: some View {
        if CloudFeature.isEnabled && app.cloudUploadEnabled {
            if let job = app.cloudUploads.job(for: recording.id) {
                if job.state == .failed { Button("Retry Upload") { app.cloudUploads.resume() } }
                Button("Cancel Upload") { Task { await app.cloudUploads.cancel(recording.id) } }
            } else if app.cloudUploads.uploaded[recording.id] != nil {
                Button("Delete from Fernsy Cloud", role: .destructive) { confirmDelete = true }
            } else if AppModel.isUploadable(recording) && app.cloud.canUpload {
                Button("Upload to Fernsy Cloud") { app.uploadToCloud(recording) }
            }
        }
    }
}

/// A recording that is only in Fernsy Cloud (its local file is gone or it came from another Mac).
struct CloudRecordingRow: View {
    @EnvironmentObject private var app: AppModel
    let item: CloudRecordingItem
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isLocked || item.isDamaged ? "lock.icloud" : "icloud")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                if let meta = item.meta {
                    Text(verbatim: meta.title).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(verbatim: meta.channel)
                        Text(verbatim: "·")
                        Text(ItemText.shortDateTime(meta.recordStart)).monospacedDigit()
                        Text(verbatim: "·")
                        Text(Duration.seconds(meta.duration).formatted(.time(pattern: .hourMinute)))
                        Text(verbatim: "·")
                        Text(ByteCountFormatter.string(fromByteCount: meta.plaintextBytes, countStyle: .file))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else {
                    Text(item.isDamaged ? "Damaged cloud recording" : "Locked cloud recording").font(.headline)
                    Text(item.isDamaged ? "Its details cannot be read." : "This device does not have the key from iCloud for it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if item.meta != nil {
                    Button("Play", systemImage: "play.fill") { app.play(cloud: item) }
                        .labelStyle(.iconOnly)
                        .help("Play")
                }
                Button("Delete", systemImage: "trash") { confirmDelete = true }
                    .labelStyle(.iconOnly)
                    .help("Delete from Fernsy Cloud")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if item.meta != nil { app.play(cloud: item) } }
        .contextMenu {
            if item.meta != nil { Button("Play") { app.play(cloud: item) } }
            Button("Delete from Fernsy Cloud", role: .destructive) { confirmDelete = true }
        }
        .cloudDeleteConfirmation(isPresented: $confirmDelete, title: item.meta?.title) {
            try? await app.cloud.delete(item)
            app.cloudUploads.forgetUploaded(cloudId: item.id)
        }
    }
}

extension View {
    /// "Delete from Fernsy Cloud?" – on all devices; the local file stays.
    func cloudDeleteConfirmation(isPresented: Binding<Bool>, title: String?, delete: @escaping () async -> Void) -> some View {
        confirmationDialog("Delete from Fernsy Cloud?", isPresented: isPresented) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("“\(title ?? String(localized: "this recording"))” is removed from Fernsy Cloud on all devices. A file on this Mac stays.")
        }
    }
}

/// Settings › Aufnahmen › Fernsy Cloud: the global switch and the account below it. There is no
/// sign-in: the account comes from the cloud key (cloud-account-from-icloud-key).
struct CloudSettingsSection: View {
    @EnvironmentObject private var app: AppModel
    @State private var enabling = false
    @State private var confirmDeleteAll = false

    var body: some View {
        let cloud = app.cloud
        Section {
            Toggle("Upload recordings to Fernsy Cloud", isOn: Binding(
                get: { app.cloudUploadEnabled },
                set: { on in
                    if !on { app.cloudUploadEnabled = false } else if cloud.canUpload { app.cloudUploadEnabled = true } else { enabling = true }
                }))
            if cloud.hasAccount, let account = cloud.account {
                LabeledContent("Subscription") { Text(verbatim: CloudModel.stateText(account)) }
                if account.totalBytes > 0 {
                    LabeledContent("Storage") { Text(verbatim: CloudModel.storageText(account)) }
                }
                if let usage = app.assistant.usageText {
                    LabeledContent("Assistant Requests") { Text(verbatim: usage) }
                }
                if let note = cloud.deletionNote {
                    Text(verbatim: note).foregroundStyle(Theme.warning)
                }
            }
            if cloud.canMoveSubscription {
                CloudMoveRow()
            }
            if case .failed(let message) = cloud.phase {
                Text(verbatim: message).foregroundStyle(Theme.warning)
            }
            if app.assistant.hasConsent {
                LabeledContent("Assistant") {
                    Button("Withdraw Consent") { app.assistant.withdrawConsent() }
                        .help("The assistant asks again before its next request")
                }
            }
            if cloud.hasAccount, cloud.account != nil {
                HStack {
                    #if DIRECT_DISTRIBUTION
                    Button("Manage Subscription…") {
                        Task { if let url = await cloud.manageSubscriptionURL() { NSWorkspace.shared.open(url) } }
                    }
                    #else
                    if cloud.account?.isWebPurchase == true {
                        // Bought outside the App Store: no link to it here (App Store guideline 3.1.3(b)).
                        Text("This subscription is managed where you bought it.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Manage Subscription…") { NSWorkspace.shared.open(CloudSettingsSection.manageURL) }
                    }
                    #endif
                    Spacer()
                    Button("Delete Fernsy Cloud Data…", role: .destructive) { confirmDeleteAll = true }
                        .accessibilityIdentifier("cloud.deleteAll")
                }
            }
        } header: {
            Text("Fernsy Cloud")
        } footer: {
            Text("While this is on, finished recordings are uploaded by themselves. They are encrypted on this Mac first: only your devices with the same Apple ID can play them, because the key stays in your iCloud. Without the key, for example after resetting iCloud data, cloud recordings cannot be played anymore.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $enabling) { CloudEnableSheet() }
        .cloudDeleteAllConfirmation(isPresented: $confirmDeleteAll) {
            app.cloudUploadEnabled = false
            try? await cloud.deleteCloudData()
            app.cloudUploads.reconcile(existing: [])
        }
        .task {
            if cloud.hasAccount { await cloud.refresh() }
            #if DEBUG
            // IPTV_TESTCLOUDDELETE=1 shows the delete confirmation, for screenshots.
            if ProcessInfo.processInfo.environment["IPTV_TESTCLOUDDELETE"] != nil { confirmDeleteAll = true }
            // IPTV_TESTCLOUDBUY=1 opens the subscribe sheet and presses Subscribe (DMG purchase tests).
            if ProcessInfo.processInfo.environment["IPTV_TESTCLOUDBUY"] != nil, !cloud.canUpload { enabling = true }
            #endif
        }
    }

    /// Apple's subscription management (macOS has no in-app sheet for it).
    static let manageURL = URL(string: "https://apps.apple.com/account/subscriptions")!
}

/// The subscription belongs to another Fernsy Cloud account, for example after the iCloud key
/// was lost: offer to move it to this key (design E).
struct CloudMoveRow: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your subscription is linked to another Fernsy Cloud key, for example from before your iCloud data was reset. Move it here to use Fernsy Cloud with this key. Recordings under the old key cannot be read anymore and are deleted after 30 days.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button("Move Subscription Here") { Task { await app.cloud.moveSubscription() } }
                .accessibilityIdentifier("cloud.move")
        }
    }
}

extension View {
    /// "Delete Fernsy Cloud data?" – everything in the cloud, on all devices; the subscription is
    /// cancelled in the App Store.
    func cloudDeleteAllConfirmation(isPresented: Binding<Bool>, delete: @escaping () async -> Void) -> some View {
        confirmationDialog("Delete all Fernsy Cloud data?", isPresented: isPresented) {
            Button("Delete All", role: .destructive) { Task { await delete() } }
        } message: {
            Text("All cloud recordings are removed on all devices. Recordings on this Mac stay. Your subscription continues until you cancel it in the App Store.")
        }
    }
}

/// Turning the switch on without an active subscription: buy or restore, nothing else.
struct CloudEnableSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cloud = app.cloud
        VStack(alignment: .leading, spacing: 16) {
            Label("Fernsy Cloud", systemImage: "icloud").font(.title2.bold())
            CloudOfferParts()
            Text("Your recordings in your own private storage – end-to-end encrypted, so nobody else can see them, not even mobilistics.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            if cloud.canMoveSubscription {
                CloudMoveRow()
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: cloud.terms.offerLine(cloud.offer)).font(.headline)
                        HStack {
                            Button("Subscribe") { Task { if await cloud.purchase() { finish() } } }
                                .buttonStyle(.borderedProminent)
                                .disabled(cloud.isPurchasing)
                            #if DIRECT_DISTRIBUTION
                            // Paid in the browser: the server learns about it from Stripe.
                            Button("Check Again") { Task { if await cloud.restore() { finish() } } }
                                .disabled(cloud.isPurchasing)
                            #else
                            Button("Restore Purchases") { Task { if await cloud.restore() { finish() } } }
                                .disabled(cloud.isPurchasing)
                            #endif
                            if cloud.isPurchasing || cloud.isAwaitingCheckout { ProgressView().controlSize(.small) }
                        }
                        #if DIRECT_DISTRIBUTION
                        if cloud.isAwaitingCheckout {
                            Text(verbatim: Self.directText("Finish the payment in your browser. Fernsy notices it by itself.",
                                                           "Schließ die Zahlung in deinem Browser ab. Fernsy bemerkt das von selbst."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: Self.directText("You pay on fernsy.app by card, Apple Pay or another method through Stripe.",
                                                           "Du bezahlst auf fernsy.app mit Karte, Apple Pay oder einer anderen Zahlart über Stripe."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        #endif
                        CloudTermsFooter(terms: cloud.terms)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if case .failed(let message) = cloud.phase {
                Text(verbatim: message).foregroundStyle(Theme.warning)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task {
            await cloud.refreshSubscription()
            #if DEBUG
            if ProcessInfo.processInfo.environment["IPTV_TESTCLOUDBUY"] != nil, await cloud.purchase() { finish() }
            #endif
        }
        .onChange(of: cloud.canUpload) { _, can in if can { finish() } }
    }

    #if DIRECT_DISTRIBUTION
    /// The DMG's texts about the website purchase stay out of the string catalog, so the App Store
    /// apps carry no hint of another way to pay (stripe-cloud-subscription design 6).
    static func directText(_ english: String, _ german: String) -> String {
        Locale.current.language.languageCode?.identifier == "de" ? german : english
    }
    #endif

    /// The switch goes on as soon as the account can upload.
    private func finish() {
        guard app.cloud.canUpload else { return }
        app.cloudUploadEnabled = true
        dismiss()
    }
}
