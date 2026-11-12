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
                    app.removeFromServer(order)
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
                    app.recordOnServer(entry, on: channel)
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

/// "Record on Server" or, for a show the server has an unfinished order for, "Remove from
/// Server": the second action beside every "Record" in menus and record questions
/// (server-recording-everywhere design 2). Nothing without a paired server or for a show that
/// is over. It gets the model handed in, because a record question's buttons have no environment.
struct ServerRecordItem: View {
    let app: AppModel
    let entry: EPGEntry
    let channel: LiveChannel

    var body: some View {
        let server = app.cloud.server
        if server.isPaired, entry.end > Date() {
            if let order = server.pendingOrder(channelId: channel.id, start: entry.start) {
                Button("Remove from Server", systemImage: "xmark.circle") { app.removeFromServer(order) }
                    .help(ServerText.describe(order.state))
            } else {
                Button("Record on Server", systemImage: "server.rack") { app.recordOnServer(entry, on: channel) }
                    .help("Fernsy Server records it, also while this Mac is off")
            }
        }
    }
}

/// The same beside the channel pane's record capsule: "On Server", or the order's state once
/// the server has it; clicking again takes the order back.
struct ServerRecordCapsule: View {
    @EnvironmentObject private var app: AppModel
    let channel: LiveChannel
    let entry: EPGEntry

    var body: some View {
        let server = app.cloud.server
        if server.isPaired, entry.end > Date() {
            let order = server.pendingOrder(channelId: channel.id, start: entry.start)
            Button {
                if let order { app.removeFromServer(order) } else { app.recordOnServer(entry, on: channel) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "server.rack").font(.caption2)
                    if let order { Text(verbatim: ServerText.phase(order.state)) } else { Text("On Server") }
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(order == nil ? Color.secondary : .white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(order == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.accentColor), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(order == nil ? LocalizedStringKey("Fernsy Server records it, also while this Mac is off") : LocalizedStringKey("Remove from Server"))
            .accessibilityIdentifier("server.capsule")
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
