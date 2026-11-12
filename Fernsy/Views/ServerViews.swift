import FernsyCore
import FernsyPlayer
import SwiftUI

/// Settings › Fernsy Server (headless-recorder): pair with the server's code, its state, remove.
struct ServerSettingsSection: View {
    @EnvironmentObject private var app: AppModel
    @State private var code = ""
    @State private var pairing = false
    @State private var failure: String?
    @State private var confirmRemove = false

    var body: some View {
        if app.cloud.canUseCloud { section }
    }

    private var section: some View {
        let server = app.cloud.server
        return Section {
            if let status = server.status, server.isPaired {
                LabeledContent("Connection") { Text(verbatim: ServerText.connection(status)) }
                    .accessibilityIdentifier("server.connection")
                if let next = status.nextStart {
                    LabeledContent("Next Recording") { Text(next, format: .dateTime.weekday().day().month().hour().minute()) }
                }
                if let free = status.freeBytes {
                    LabeledContent("Free Space") { Text(verbatim: CloudUploadQueue.bytes(free)) }
                }
                if let error = status.error, status.loginRefused != true {
                    Text(verbatim: error).foregroundStyle(Theme.warning)
                }
                if let login = status.login {
                    LabeledContent("Records With") { Text(verbatim: login) }
                        .accessibilityIdentifier("server.login")
                }
                if let note = ServerText.loginNote(status, checking: server.isCheckingLogin) {
                    Text(verbatim: note)
                        .foregroundStyle(ServerText.loginNoteIsWarning(status, checking: server.isCheckingLogin) ? Theme.warning : .secondary)
                }
                HStack {
                    if let credentials = app.credentials {
                        Button("Use This Login") { Task { try? await server.useLogin(credentials) } }
                            .disabled(server.isCheckingLogin)
                            .help("Sends the login this Mac signs in with, for example after a new password. The server checks it with the provider before it uses it.")
                            .accessibilityIdentifier("server.useLogin")
                    }
                    Spacer()
                    Button("Remove Server…", role: .destructive) { confirmRemove = true }
                        .accessibilityIdentifier("server.remove")
                }
            } else if server.isRemoving {
                Text("Waiting for the server to confirm the removal …").foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField("Code from the server", text: $code, prompt: Text(verbatim: "7K3Q-ABCDEF"))
                        .font(.body.monospaced())
                        .accessibilityIdentifier("server.code")
                        .onSubmit(pair)
                    Button("Pair", action: pair)
                        .disabled(pairing || code.isEmpty || app.credentials == nil)
                        .accessibilityIdentifier("server.pair")
                    if pairing { ProgressView().controlSize(.small) }
                }
                if let failure { Text(verbatim: failure).foregroundStyle(Theme.warning) }
            }
        } header: {
            Text("Fernsy Server")
        } footer: {
            Text("Fernsy Server records your shows around the clock on a computer at home – a NAS, a home server or a Raspberry Pi – and puts them into Fernsy Cloud, also while this Mac is off. Enter the code it shows on its status page or in its log; it gets your IPTV login and the key for Fernsy Cloud, encrypted for this server only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { server.startPolling() }
        .onDisappear { server.stopPolling() }
        .confirmationDialog("Remove Fernsy Server?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { Task { try? await server.remove() } }
        } message: {
            Text("The server deletes the keys, the login and recordings it has not uploaded yet, and shows a new code.")
        }
    }

    private func pair() {
        guard let login = app.credentials, !code.isEmpty, !pairing else { return }
        pairing = true
        failure = nil
        Task {
            do {
                try await app.cloud.server.pair(code: code, login: login)
                code = ""
            } catch let error as ServerModel.PairingFailure {
                failure = ServerText.pairing(error)
            } catch {
                failure = ServerText.pairing(.network("\(error)"))
            }
            pairing = false
        }
    }
}

/// Under "Record" in a show's detail: record on the server instead, or the order's state.
struct ServerRecordButton: View {
    @EnvironmentObject private var app: AppModel
    let entry: EPGEntry
    let channel: LiveChannel

    var body: some View {
        let server = app.cloud.server
        if server.isPaired, entry.end > Date() {
            if let order = server.order(channelId: channel.id, start: entry.start) {
                Button {
                    Task { try? await server.cancel(order.id) }
                } label: {
                    Text("Remove from Server").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help(ServerText.describe(order.state))
                .accessibilityIdentifier("server.cancel")
                Text(verbatim: ServerText.describe(order.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("server.orderState")
            } else {
                Button {
                    let padding = Recorder.padding
                    let order = ControlOrder(channelId: channel.id, channelName: channel.displayName, title: entry.title,
                                             showStart: entry.start, showEnd: entry.end, padBefore: padding.before, padAfter: padding.after,
                                             createdBy: Host.current().localizedName ?? "Mac")
                    Task {
                        do {
                            try await server.schedule(order)
                            // The order waits in Fernsy Control; say so when the server is away right now.
                            await server.refresh()
                            if !server.isOnline() { Prompt.inform(title: String(localized: "Recording on Fernsy Server"), message: ServerText.offline) }
                        } catch {
                            Prompt.inform(title: String(localized: "Can’t Record"), message: ServerText.pairing(.network("\(error)")))
                        }
                    }
                } label: {
                    Text("Record on Server").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Fernsy Server records it, also while this Mac is off")
                .accessibilityIdentifier("server.record")
            }
        }
    }
}

/// The server's orders that are not in Fernsy Cloud yet, in Recordings.
struct ServerOrdersSection: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let server = app.cloud.server
        let rows = server.orders.filter { $0.state?.phase != .done }
        if server.isPaired, !rows.isEmpty {
            Section("On Fernsy Server") {
                ForEach(rows) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: row.order.title).font(.headline)
                            Text(verbatim: "\(row.order.channelName) · \(row.order.showStart.formatted(.dateTime.weekday().day().month().hour().minute()))")
                                .foregroundStyle(.secondary)
                            Text(verbatim: ServerText.describe(row.state))
                                .font(.caption)
                                .foregroundStyle(row.state?.phase == .failed || row.state?.phase == .refused ? Theme.warning : .secondary)
                        }
                        Spacer()
                    }
                    .accessibilityIdentifier("server.order.\(row.id)")
                    .contextMenu {
                        Button(row.state?.isFinished == true ? LocalizedStringKey("Remove") : LocalizedStringKey("Remove from Server"), role: .destructive) {
                            Task { try? await server.cancel(row.id) }
                        }
                    }
                }
            }
        }
    }
}
