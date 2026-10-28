import FernsyCore
import SwiftUI

/// First launch (design screen `login`): what Fernsy is and which account to add.
/// Logins of the user's other devices found in iCloud (icloud-sync): one click signs in.
private struct SyncedLoginsRow: View {
    @EnvironmentObject private var model: TVModel
    @State private var working = false
    @State private var error: String?

    var body: some View {
        if model.syncedXtream != nil || model.syncedJellyfin != nil {
            VStack(spacing: 18) {
                Label("From Your iCloud", systemImage: "icloud").font(.system(size: 24, weight: .semibold)).foregroundStyle(TVTheme.secondary)
                HStack(spacing: 24) {
                    if let login = model.syncedXtream {
                        Button { use { await model.signIn(login); if case .failed(let message) = model.signIn { error = message } } } label: {
                            label("IPTV", login.server, login.username)
                        }
                        .buttonStyle(TVPillStyle())
                        .accessibilityIdentifier("welcome.synced.iptv")
                    }
                    if let login = model.syncedJellyfin {
                        Button {
                            use {
                                do { try await model.jellyfin.signIn(server: login.server, username: login.username, password: login.password) } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        } label: {
                            label("Jellyfin", login.server, login.username)
                        }
                        .buttonStyle(TVPillStyle(prominent: false))
                        .accessibilityIdentifier("welcome.synced.jellyfin")
                    }
                }
                .disabled(working)
                if let error = error ?? model.iCloudSignInError {
                    Text(verbatim: error).font(.system(size: 22)).foregroundStyle(TVTheme.warning).accessibilityIdentifier("welcome.synced.error")
                }
            }
            .padding(.top, 50)
        }
    }

    private func label(_ kind: String, _ server: String, _ user: String) -> some View {
        Text("Use \(kind): \(URL(string: server)?.host() ?? server) · \(user)")
    }

    private func use(_ signIn: @escaping () async -> Void) {
        working = true
        error = nil
        Task {
            await signIn()
            working = false
        }
    }
}

struct WelcomeScreen: View {
    @State private var showIPTV = false
    @State private var showJellyfin = false

    var body: some View {
        NavigationStack {
            ZStack {
                RadialGradient(colors: [Color(hex: 0xE88C6E, opacity: 0.28), Color(hex: 0x9650A0, opacity: 0.18), .clear],
                               center: UnitPoint(x: 0.5, y: 1.2), startRadius: 0, endRadius: 1100)
                    .ignoresSafeArea()
                VStack(spacing: 22) {
                    Image("FernsyIcon").resizable().frame(width: 170, height: 170)
                    Text("Welcome to Fernsy")
                        .font(.system(size: 60, weight: .bold))
                    Text("What would you like to connect? You can add more accounts later in Settings.")
                        .font(.system(size: 26))
                        .foregroundStyle(TVTheme.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .frame(maxWidth: 900)
                    HStack(spacing: 48) {
                        Button { showIPTV = true } label: {
                            AccountTypeCard(symbol: "dot.radiowaves.left.and.right", title: "IPTV Account",
                                            detail: "Live TV, guide, films and series from your provider (Xtream Codes).")
                        }
                        .buttonStyle(TVTileStyle(radius: 28, scale: 1.06))
                        .accessibilityIdentifier("welcome.iptv")
                        Button { showJellyfin = true } label: {
                            AccountTypeCard(symbol: "play.rectangle.fill", title: "Jellyfin Server",
                                            detail: "Your own library with films, series and watched state.")
                        }
                        .buttonStyle(TVTileStyle(rest: .white.opacity(0.07), radius: 28, scale: 1.06))
                        .accessibilityIdentifier("welcome.jellyfin")
                    }
                    .padding(.top, 80)
                    SyncedLoginsRow()
                    Spacer()
                    Text("Fernsy brings no content. You need your own account with a provider or a Jellyfin server.")
                        .font(.system(size: 20))
                        .foregroundStyle(TVTheme.tertiary)
                }
                .padding(.top, 50)
                .padding(.bottom, 20)
            }
            .foregroundStyle(TVTheme.text)
            .navigationDestination(isPresented: $showIPTV) { IPTVSignInScreen() }
            .navigationDestination(isPresented: $showJellyfin) { JellyfinSignInScreen() }
        }
    }
}

private struct AccountTypeCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .frame(width: 64, height: 64)
                .foregroundStyle(focused ? TVTheme.accent : TVTheme.accentSoft)
                .background(focused ? TVTheme.accent.opacity(0.14) : TVTheme.accentLight.opacity(0.18), in: .rect(cornerRadius: 18))
            Text(title).font(.system(size: 34, weight: .bold))
            Text(detail).font(.system(size: 22)).lineSpacing(6).opacity(0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .frame(width: 520, alignment: .leading)
    }
}

/// The IPTV form (design screen `login2`): server, username, password; typing works from the
/// iPhone through tvOS' keyboard notification. "Try the Demo" signs in to the demo server.
struct IPTVSignInScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case server, username, password, submit }

    static let demo = XtreamCredentials(server: "https://fernsy-demo.mobilistics.workers.dev", username: "demo", password: "demo")

    private var busy: Bool { model.signIn == .signingIn }

    var body: some View {
        HStack(alignment: .center, spacing: 150) {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundStyle(TVTheme.accentSoft)
                    .frame(width: 84, height: 84)
                    .background(TVTheme.accentLight.opacity(0.18), in: .rect(cornerRadius: 24))
                Text("Add IPTV Account")
                    .font(.system(size: 54, weight: .bold))
                Text("You find these details in your provider’s email under “Xtream Codes”. They are kept in the keychain.")
                    .font(.system(size: 24))
                    .lineSpacing(8)
                    .foregroundStyle(TVTheme.secondary)
                HStack(spacing: 18) {
                    Image(systemName: "iphone")
                        .font(.system(size: 28))
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.12), in: .rect(cornerRadius: 14))
                    Text("A notification appears on your iPhone. With it you can type or paste the address and password.")
                        .font(.system(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(TVTheme.text.opacity(0.8))
                }
                .padding(24)
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 20))
                .padding(.top, 16)
            }
            .frame(width: 640)

            VStack(alignment: .leading, spacing: 18) {
                TVFormField(label: "Server Address", text: $server, content: .url)
                    .focused($focus, equals: .server).accessibilityIdentifier("signin.server")
                TVFormField(label: "Username", text: $username, content: .username)
                    .focused($focus, equals: .username).accessibilityIdentifier("signin.username")
                TVFormField(label: "Password", text: $password, content: .password)
                    .focused($focus, equals: .password).accessibilityIdentifier("signin.password")
                    // Down lands on "Sign In", not on the closer demo button.
                    .onMoveCommand { if $0 == .down { focus = .submit } }
                if case .failed(let message) = model.signIn {
                    Text(message)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(TVTheme.warning)
                        .accessibilityIdentifier("signin.error")
                }
                HStack(spacing: 20) {
                    Button {
                        Task { await model.signIn(XtreamCredentials(server: server, username: username, password: password)) }
                    } label: {
                        if busy { ProgressView() } else { Text("Sign In") }
                    }
                    .buttonStyle(TVPillStyle())
                    .disabled(server.isEmpty || username.isEmpty || password.isEmpty || busy)
                    .focused($focus, equals: .submit)
                    .accessibilityIdentifier("signin.submit")
                    Button("Try the Demo") {
                        Task { await model.signIn(Self.demo) }
                    }
                    .buttonStyle(TVPillStyle(prominent: false))
                    .disabled(busy)
                    .accessibilityIdentifier("signin.demo")
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 90)
        .foregroundStyle(TVTheme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TVTheme.background)
    }
}

/// The Jellyfin form: server, username, password; signs in as on the Mac.
struct JellyfinSignInScreen: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case server, username, password, submit }

    var body: some View {
        HStack(alignment: .center, spacing: 150) {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(TVTheme.accentSoft)
                    .frame(width: 84, height: 84)
                    .background(TVTheme.accentLight.opacity(0.18), in: .rect(cornerRadius: 24))
                Text("Add Jellyfin Server").font(.system(size: 54, weight: .bold))
                Text("The address of your Jellyfin server, for example http://192.168.1.20:8096, and your user. They are kept in the keychain.")
                    .font(.system(size: 24)).lineSpacing(8).foregroundStyle(TVTheme.secondary)
            }
            .frame(width: 640)
            VStack(alignment: .leading, spacing: 18) {
                TVFormField(label: "Server Address", text: $server, content: .url)
                    .focused($focus, equals: .server).accessibilityIdentifier("jfsignin.server")
                TVFormField(label: "Username", text: $username, content: .username)
                    .focused($focus, equals: .username).accessibilityIdentifier("jfsignin.username")
                TVFormField(label: "Password", text: $password, content: .password)
                    .focused($focus, equals: .password).accessibilityIdentifier("jfsignin.password")
                    .onMoveCommand { if $0 == .down { focus = .submit } }
                if let error {
                    Text(verbatim: error).font(.system(size: 22, weight: .medium)).foregroundStyle(TVTheme.warning)
                        .accessibilityIdentifier("jfsignin.error")
                }
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            try await model.jellyfin.signIn(server: server, username: username, password: password)
                            error = nil
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                } label: {
                    if busy { ProgressView() } else { Text("Sign In") }
                }
                .buttonStyle(TVPillStyle())
                .disabled(server.isEmpty || username.isEmpty || busy)
                .focused($focus, equals: .submit)
                .accessibilityIdentifier("jfsignin.submit")
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 90)
        .foregroundStyle(TVTheme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TVTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
    }
}
