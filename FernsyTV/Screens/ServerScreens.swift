import FernsyCore
import FernsyPlayer
import SwiftUI

/// Settings › Fernsy Cloud › Fernsy Server (headless-recorder): pair with the server's code,
/// its state, remove.
struct ServerSettingsScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var code = ""
    @State private var pairing = false
    @State private var failure: String?
    @State private var confirmRemove = false

    var body: some View {
        let server = model.cloud.server
        SettingsPage(title: "Fernsy Server") {
            Text("Fernsy Server records your shows around the clock on a computer at home – a NAS, a home server or a Raspberry Pi – and puts them into Fernsy Cloud, also while this Apple TV sleeps.")
                .font(.system(size: 24)).foregroundStyle(TVTheme.secondary).padding(.bottom, 10)
            if let status = server.status, server.isPaired {
                SettingsRow(title: Text("Connection"), value: Text(verbatim: ServerText.connection(status)))
                    .accessibilityIdentifier("server.connection")
                if let next = status.nextStart {
                    SettingsRow(title: Text("Next Recording"), value: Text(next, format: .dateTime.weekday().day().month().hour().minute()))
                }
                if let free = status.freeBytes {
                    SettingsRow(title: Text("Free Space"), value: Text(verbatim: CloudUploadQueue.bytes(free)))
                }
                if let error = status.error, status.loginRefused != true {
                    Text(verbatim: error).font(.system(size: 22)).foregroundStyle(TVTheme.warning)
                }
                if let login = status.login {
                    SettingsRow(title: Text("Records With"), value: Text(verbatim: login))
                        .accessibilityIdentifier("server.login")
                }
                if let note = ServerText.loginNote(status, checking: server.isCheckingLogin) {
                    Text(verbatim: note).font(.system(size: 22))
                        .foregroundStyle(ServerText.loginNoteIsWarning(status, checking: server.isCheckingLogin) ? TVTheme.warning : TVTheme.secondary)
                }
                if let credentials = model.credentials {
                    Button { Task { try? await server.useLogin(credentials) } } label: { SettingsRow(title: Text("Use This Login")) }
                        .disabled(server.isCheckingLogin)
                        .accessibilityIdentifier("server.useLogin")
                }
                Button(role: .destructive) { confirmRemove = true } label: { SettingsRow(title: Text("Remove Server")) }
                    .accessibilityIdentifier("server.remove")
            } else if server.isRemoving {
                Text("Waiting for the server to confirm the removal …").font(.system(size: 24)).foregroundStyle(TVTheme.secondary)
            } else if model.credentials == nil {
                Text("Sign in to an IPTV account first: the server records with it.").font(.system(size: 24)).foregroundStyle(TVTheme.secondary)
            } else {
                TextField("Code from the server", text: $code)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .font(.system(size: 30, design: .monospaced))
                    .accessibilityIdentifier("server.code")
                    .onSubmit(pair)
                Button(action: pair) {
                    SettingsRow(title: Text(pairing ? "Pairing …" : "Pair"))
                }
                .disabled(pairing || code.isEmpty)
                .accessibilityIdentifier("server.pair")
                if let failure { Text(verbatim: failure).font(.system(size: 22)).foregroundStyle(TVTheme.warning) }
                Text("The server shows its code on its status page and in its log. It gets your IPTV login and the key for Fernsy Cloud, encrypted for this server only.")
                    .font(.system(size: 20)).foregroundStyle(TVTheme.secondary)
            }
        }
        .onAppear { server.startPolling() }
        .onDisappear { server.stopPolling() }
        .confirmationDialog("Remove Fernsy Server?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { try? await server.remove() } }
        } message: {
            Text("The server deletes the keys, the login and recordings it has not uploaded yet, and shows a new code.")
        }
    }

    private func pair() {
        guard let login = model.credentials, !code.isEmpty, !pairing else { return }
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

/// Inside a show's "Record" dialog: record it on the server, or take it off the server.
struct ServerDialogButtons: View {
    @EnvironmentObject private var model: TVModel
    let show: EPGEntry
    let channel: LiveChannel

    var body: some View {
        let server = model.cloud.server
        if server.isPaired, show.end > Date() {
            if let order = server.order(channelId: channel.id, start: show.start) {
                Button("Remove from Server", role: .destructive) { Task { try? await server.cancel(order.id) } }
            } else {
                Button("Record on Fernsy Server") {
                    Task {
                        do {
                            _ = try await model.orderOnServer(show, on: channel)
                            // Its state was just read: say so when the server is away right now.
                            if !server.isOnline() { model.notice = ServerText.offline }
                        } catch {
                            model.notice = ServerText.order(caught: error)
                        }
                    }
                }
            }
        }
    }
}

/// The server's orders that are not in Fernsy Cloud yet, in Recordings.
struct ServerShelf: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        let server = model.cloud.server
        let rows = server.orders.filter { $0.state?.phase != .done }
        if server.isPaired, !rows.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Fernsy Server").font(.system(size: 30, weight: .bold))
                    Text(verbatim: "\(rows.count)").font(.system(size: 21)).foregroundStyle(TVTheme.text.opacity(0.55))
                }
                EdgeToEdgeRow(margin: 90) {
                    LazyHStack(alignment: .top, spacing: 36) {
                        ForEach(rows) { ServerOrderCard(row: $0) }
                    }
                    .padding(.vertical, 20)
                }
            }
            .focusSection()
            .accessibilityIdentifier("recordings.server")
        }
    }
}

private struct ServerOrderCard: View {
    @EnvironmentObject private var model: TVModel
    let row: ServerModel.Order
    @State private var asked = false

    var body: some View {
        let failed = row.state?.phase == .failed || row.state?.phase == .refused
        Button { asked = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: failed ? "exclamationmark.triangle" : "server.rack").font(.system(size: 30))
                    .foregroundStyle(failed ? TVTheme.warning : TVTheme.secondary)
                Text(verbatim: row.order.title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                Text(verbatim: "\(row.order.channelName) · \(ItemText.shortDateTime(row.order.showStart))")
                    .font(.system(size: 20)).foregroundStyle(TVTheme.secondary).lineLimit(1)
                Text(verbatim: ServerText.describe(row.state)).font(.system(size: 18))
                    .foregroundStyle(failed ? TVTheme.warning : TVTheme.secondary).lineLimit(3)
            }
            .padding(24)
            .frame(width: 420, height: 240, alignment: .topLeading)
        }
        .buttonStyle(TVTileStyle(rest: .white.opacity(0.06), radius: 16, scale: 1.05))
        .accessibilityIdentifier("server.order.\(row.id)")
        .confirmationDialog(row.order.title, isPresented: $asked, titleVisibility: .visible) {
            Button(row.state?.isFinished == true ? LocalizedStringKey("Remove") : LocalizedStringKey("Remove from Server"), role: .destructive) {
                Task { try? await model.cloud.server.cancel(row.id) }
            }
        } message: {
            Text(verbatim: ServerText.describe(row.state))
        }
    }
}
