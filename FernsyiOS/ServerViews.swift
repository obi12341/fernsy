import FernsyCore
import FernsyPlayer
import SwiftUI

/// Settings › Fernsy Cloud › Fernsy Server (headless-recorder): pair with the server's code,
/// see its state, remove it.
struct ServerSettingsView: View {
    @EnvironmentObject private var model: TVModel
    @State private var code = ""
    @State private var pairing = false
    @State private var failure: String?
    @State private var confirmRemove = false

    var body: some View {
        let server = model.cloud.server
        Form {
            Section {
                Text("Fernsy Server records your shows around the clock on a computer at home – a NAS, a home server or a Raspberry Pi – and puts them into Fernsy Cloud. Then iPhone and iPad can schedule recordings too.")
            }
            if let status = server.status, server.isPaired {
                Section("Server") {
                    LabeledContent("Connection", value: ServerText.connection(status))
                        .accessibilityIdentifier("server.connection")
                    if let next = status.nextStart {
                        LabeledContent("Next Recording", value: next.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let free = status.freeBytes {
                        LabeledContent("Free Space", value: CloudUploadQueue.bytes(free))
                    }
                    if let error = status.error, status.loginRefused != true {
                        Text(verbatim: error).foregroundStyle(TVTheme.warning)
                    }
                }
                Section {
                    if let login = status.login {
                        LabeledContent("Records With", value: login).accessibilityIdentifier("server.login")
                    }
                    if let note = ServerText.loginNote(status, checking: server.isCheckingLogin) {
                        Text(verbatim: note)
                            .foregroundStyle(ServerText.loginNoteIsWarning(status, checking: server.isCheckingLogin) ? TVTheme.warning : TVTheme.secondary)
                            .accessibilityIdentifier("server.loginNote")
                    }
                    if let credentials = model.credentials {
                        Button("Use This Login") { Task { try? await server.useLogin(credentials) } }
                            .disabled(server.isCheckingLogin)
                            .accessibilityIdentifier("server.useLogin")
                    }
                } header: {
                    Text("IPTV Login")
                } footer: {
                    Text("Sends the login this device signs in with, for example after a new password. The server checks it with the provider before it uses it.")
                }
                Section {
                    Button("Remove Server", role: .destructive) { confirmRemove = true }
                        .accessibilityIdentifier("server.remove")
                } footer: {
                    Text("The server deletes the keys, the login and recordings it has not uploaded yet, and shows a new code.")
                }
            } else if server.isRemoving {
                Section { Text("Waiting for the server to confirm the removal …").foregroundStyle(TVTheme.secondary) }
            } else {
                Section {
                    TextField("Code from the server", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .accessibilityIdentifier("server.code")
                    Button {
                        pair()
                    } label: {
                        HStack {
                            Text("Pair")
                            if pairing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(pairing || code.isEmpty || model.credentials == nil)
                    .accessibilityIdentifier("server.pair")
                    if let failure { Text(verbatim: failure).foregroundStyle(TVTheme.warning) }
                } header: {
                    Text("Pair")
                } footer: {
                    if model.credentials == nil {
                        Text("Sign in to an IPTV account first: the server records with it.")
                    } else {
                        Text("The server shows its code on its status page and in its log. It gets your IPTV login and the key for Fernsy Cloud, encrypted for this server only.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Fernsy Server")
        .onAppear { server.startPolling() }
        .onDisappear { server.stopPolling() }
        .confirmationDialog("Remove Fernsy Server?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { try? await server.remove() } }
        }
        .accessibilityIdentifier("server.settings")
    }

    private func pair() {
        guard let login = model.credentials else { return }
        pairing = true
        failure = nil
        Task {
            do {
                try await model.cloud.server.pair(code: code, login: login)
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

/// In a show's sheet: record it on the server, or its order's state with Cancel.
struct ServerRecordButton: View {
    @EnvironmentObject private var model: TVModel
    let show: EPGEntry
    let channel: LiveChannel
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        let server = model.cloud.server
        if server.isPaired, show.end > Date() {
            VStack(alignment: .leading, spacing: 10) {
                if let order = server.order(channelId: channel.id, start: show.start) {
                    Label(ServerText.describe(order.state), systemImage: "server.rack")
                        .foregroundStyle(TVTheme.secondary)
                        .accessibilityIdentifier("server.orderState")
                    if !(order.state?.isFinished ?? false) {
                        Button(role: .destructive) {
                            Task { try? await server.cancel(order.id) }
                        } label: {
                            Label("Cancel Recording", systemImage: "xmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ActionButtonStyle())
                    }
                } else {
                    Button {
                        schedule(server)
                    } label: {
                        Label("Record on Fernsy Server", systemImage: "record.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(busy)
                    .accessibilityIdentifier("server.record")
                }
                if let failure { Text(verbatim: failure).foregroundStyle(TVTheme.warning) }
                if !server.isOnline() {
                    Text("The server has not reported for a while; it records once it is back.").font(.footnote).foregroundStyle(TVTheme.secondary)
                }
            }
        }
    }

    private func schedule(_ server: ServerModel) {
        busy = true
        failure = nil
        let padding = Recorder.padding
        let order = ControlOrder(channelId: channel.id, channelName: channel.displayName, title: show.title,
                                 showStart: show.start, showEnd: show.end, padBefore: padding.before, padAfter: padding.after,
                                 createdBy: UIDevice.current.name)
        Task {
            do { try await server.schedule(order) } catch { failure = ServerText.pairing(.network("\(error)")) }
            busy = false
        }
    }
}

/// The server's orders that are not in Fernsy Cloud yet, at the top of Recordings.
struct ServerOrdersSection: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        let server = model.cloud.server
        let rows = server.orders.filter { $0.state?.phase != .done }
        if server.isPaired, !rows.isEmpty {
            Section("Fernsy Server") {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: row.order.title).font(.headline).lineLimit(1)
                        Text(verbatim: "\(row.order.channelName) · \(ItemText.shortDateTime(row.order.showStart))")
                            .font(.subheadline).foregroundStyle(TVTheme.secondary)
                        Text(verbatim: ServerText.describe(row.state)).font(.footnote)
                            .foregroundStyle(row.state?.phase == .failed || row.state?.phase == .refused ? TVTheme.warning : TVTheme.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("server.order.\(row.id)")
                    .swipeActions {
                        Button(row.state?.isFinished == true ? LocalizedStringKey("Remove") : LocalizedStringKey("Cancel"), role: .destructive) {
                            Task { try? await server.cancel(row.id) }
                        }
                    }
                }
            }
        }
    }
}
