import FernsyCore
import FernsyPlayer
import SwiftUI

enum AccountKind: String, CaseIterable, Identifiable {
    case iptv, jellyfin
    var id: String { rawValue }
}

struct LoginView: View {
    @State private var kind: AccountKind = .iptv

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(spacing: 6) {
                Text("Welcome to Fernsy").font(.largeTitle.weight(.semibold))
                Text("What would you like to connect to?").foregroundStyle(.secondary)
            }
            SyncedLogins()
            HStack(spacing: 12) {
                AccountKindCard(kind: .iptv, selection: $kind)
                AccountKindCard(kind: .jellyfin, selection: $kind)
            }
            .frame(width: 520)

            switch kind {
            case .iptv: IPTVSignInForm()
            case .jellyfin: JellyfinSignInForm()
            }
            Spacer(minLength: 0)
            Label("Fernsy collects no data. Credentials stay in this Mac’s keychain.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 640, minHeight: 680)
        #if DEBUG
        .task { await debugLogin() }
        #endif
    }

    #if DEBUG
    /// IPTV_TESTLOGIN=<iptv|jellyfin>|<server>|<user>|<pass> fills the form and submits it.
    private func debugLogin() async {
        guard let text = ProcessInfo.processInfo.environment["IPTV_TESTLOGIN"] else { return }
        let parts = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, let target = AccountKind(rawValue: parts[0]) else { return }
        kind = target
        try? await Task.sleep(for: .seconds(1))
        NotificationCenter.default.post(name: .debugSignIn, object: Array(parts.dropFirst()))
    }
    #endif
}

#if DEBUG
extension Notification.Name {
    static let debugSignIn = Notification.Name("Fernsy.debugSignIn")
}
#endif

/// Logins of the user's other devices found in iCloud (icloud-sync): one click signs in.
private struct SyncedLogins: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var jellyfin: JellyfinStore
    @State private var working: AccountKind?
    @State private var error: Error?

    var body: some View {
        if app.syncedXtream != nil || app.syncedJellyfin != nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("From Your iCloud", systemImage: "icloud").font(.headline)
                if let login = app.syncedXtream {
                    row(.iptv, "IPTV Provider", login.server, login.username) { try await app.login(login) }
                }
                if let login = app.syncedJellyfin {
                    row(.jellyfin, "Jellyfin Server", login.server, login.username) {
                        try await jellyfin.signIn(server: login.server, username: login.username, password: login.password)
                    }
                }
                if let message = error?.localizedDescription ?? app.iCloudSignInError {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.callout).foregroundStyle(Theme.record)
                }
            }
            .padding(14)
            .frame(width: 520, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        }
    }

    private func row(_ kind: AccountKind, _ title: LocalizedStringKey, _ server: String, _ user: String,
                     signIn: @escaping () async throws -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(verbatim: "\(URL(string: server)?.host() ?? server) · \(user)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                working = kind
                error = nil
                Task {
                    do { try await signIn() } catch { self.error = error }
                    working = nil
                }
            } label: {
                if working == kind { ProgressView().controlSize(.small) } else { Text("Use") }
            }
            .disabled(working != nil)
        }
    }
}

/// One of the two account types on the login screen.
private struct AccountKindCard: View {
    let kind: AccountKind
    @Binding var selection: AccountKind

    var body: some View {
        let selected = selection == kind
        Button { selection = kind } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind == .iptv ? "antenna.radiowaves.left.and.right" : "server.rack")
                    .font(.title2)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind == .iptv ? "IPTV Provider" : "Jellyfin Server").font(.headline)
                    Text(kind == .iptv ? "Xtream Codes" : "Your own media server")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(kind == .iptv ? "Live TV, guide, movies and series from your provider" : "Movies and series from your own server")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Which fields a sign-in error concerns.
enum SignInErrorField {
    case server, credentials, general

    init(_ error: Error) {
        switch error {
        case XtreamError.invalidServer, JellyfinError.invalidURL, JellyfinError.notJellyfin: self = .server
        case XtreamError.authFailed, JellyfinError.wrongCredentials, JellyfinError.unauthorized: self = .credentials
        case XtreamError.http(let code), JellyfinError.http(let code):
            self = code == 401 || code == 403 ? .credentials : .general
        case let error as URLError:
            switch error.code {
            case .cannotFindHost, .cannotConnectToHost, .timedOut, .dnsLookupFailed, .unsupportedURL,
                 .badURL, .secureConnectionFailed, .serverCertificateUntrusted, .networkConnectionLost:
                self = .server
            default: self = .general
            }
        default: self = .general
        }
    }
}

/// Server, username and password with an error below the fields it concerns.
private struct SignInFields: View {
    @Binding var server: String
    @Binding var username: String
    @Binding var password: String
    let serverPrompt: String
    let error: Error?

    var body: some View {
        let field = error.map(SignInErrorField.init)
        VStack(alignment: .leading, spacing: 10) {
            FieldGroup(failed: field == .server) {
                TextField("Server", text: $server, prompt: Text(verbatim: serverPrompt))
            }
            if field == .server, let error { ErrorLine(error: error) }
            FieldGroup(failed: field == .credentials) {
                TextField("Username", text: $username)
                Divider()
                SecureField("Password", text: $password)
            }
            if field == .credentials || field == .general, let error { ErrorLine(error: error) }
        }
        .frame(width: 420)
    }

    private struct FieldGroup<Content: View>: View {
        let failed: Bool
        @ViewBuilder let content: Content

        var body: some View {
            VStack(spacing: 8) { content }
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(failed ? AnyShapeStyle(Theme.record) : AnyShapeStyle(.separator), lineWidth: failed ? 1.5 : 1)
                )
        }
    }

    private struct ErrorLine: View {
        let error: Error

        var body: some View {
            Label(error.localizedDescription, systemImage: "exclamationmark.circle.fill")
                .font(.callout)
                .foregroundStyle(Theme.record)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Xtream Codes sign-in (login screen and Settings).
struct IPTVSignInForm: View {
    @EnvironmentObject private var app: AppModel
    var onDone: () -> Void = {}
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 18) {
            SignInFields(server: $server, username: $username, password: $password,
                         serverPrompt: "http://server:8080", error: error)
                .disabled(isWorking)
                .onSubmit(login)

            Button(action: login) {
                if isWorking {
                    ProgressView().controlSize(.small).frame(width: 120)
                } else {
                    Text("Sign In").frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isWorking || server.isEmpty || username.isEmpty || password.isEmpty)
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugSignIn)) { note in
            guard let values = note.object as? [String] else { return }
            server = values[0]; username = values[1]; password = values[2]
            login()
        }
        #endif
    }

    private func login() {
        guard !server.isEmpty, !username.isEmpty, !password.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        let creds = XtreamCredentials(server: server, username: username, password: password)
        Task {
            do {
                try await app.login(creds)
                onDone()
            } catch {
                self.error = error
            }
            isWorking = false
        }
    }
}

/// Jellyfin sign-in (login screen, Settings and "sign in again").
struct JellyfinSignInForm: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    var prefillServer: String? = nil
    var prefillUser: String? = nil
    var onDone: () -> Void = {}
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 18) {
            SignInFields(server: $server, username: $username, password: $password,
                         serverPrompt: "https://jellyfin.example.com", error: error)
                .disabled(isWorking)
                .onSubmit(signIn)

            Button(action: signIn) {
                if isWorking {
                    ProgressView().controlSize(.small).frame(width: 120)
                } else {
                    Text("Sign In").frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isWorking || server.isEmpty || username.isEmpty)
        }
        .onAppear {
            if server.isEmpty, let prefillServer { server = prefillServer }
            if username.isEmpty, let prefillUser { username = prefillUser }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugSignIn)) { note in
            guard let values = note.object as? [String] else { return }
            server = values[0]; username = values[1]; password = values[2]
            signIn()
        }
        #endif
    }

    private func signIn() {
        guard !server.isEmpty, !username.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            do {
                try await jellyfin.signIn(server: server, username: username, password: password)
                onDone()
            } catch {
                self.error = error
            }
            isWorking = false
        }
    }
}
