import FernsyCore
import SwiftUI

/// First launch: what Fernsy is and which account to add, plus the logins found in iCloud.
struct WelcomeView: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image("FernsyIcon").resizable().frame(width: 96, height: 96).padding(.top, 40)
                    Text("Welcome to Fernsy").font(.largeTitle.bold())
                    Text("What would you like to connect? You can add more accounts later in Settings.")
                        .font(.body).foregroundStyle(TVTheme.secondary).multilineTextAlignment(.center)
                    VStack(spacing: 14) {
                        NavigationLink { IPTVSignInView() } label: {
                            AccountCard(symbol: "dot.radiowaves.left.and.right", title: "IPTV Account",
                                        detail: "Live TV, guide, movies and series from your provider (Xtream Codes).")
                        }
                        .accessibilityIdentifier("welcome.iptv")
                        NavigationLink { JellyfinSignInView() } label: {
                            AccountCard(symbol: "play.rectangle.fill", title: "Jellyfin Server",
                                        detail: "Your own library with movies, series and watched state.")
                        }
                        .accessibilityIdentifier("welcome.jellyfin")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    SyncedLogins()
                    Text("Fernsy brings no content. You need your own account with a provider or a Jellyfin server.")
                        .font(.footnote).foregroundStyle(TVTheme.tertiary).multilineTextAlignment(.center).padding(.top, 30)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(TVTheme.background.ignoresSafeArea())
        }
    }
}

private struct AccountCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 48, height: 48)
                .foregroundStyle(TVTheme.accentSoft)
                .background(TVTheme.accentLight.opacity(0.18), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(TVTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(TVTheme.tertiary)
        }
        .padding(18)
        .background(TVTheme.tile, in: .rect(cornerRadius: 18))
        .contentShape(.rect)
    }
}

/// Logins of the user's other devices found in iCloud (icloud-sync): one tap signs in.
private struct SyncedLogins: View {
    @EnvironmentObject private var model: TVModel
    @State private var working = false
    @State private var error: String?

    var body: some View {
        if model.syncedXtream != nil || model.syncedJellyfin != nil {
            VStack(spacing: 12) {
                Label("From Your iCloud", systemImage: "icloud").font(.subheadline.weight(.semibold)).foregroundStyle(TVTheme.secondary)
                if let login = model.syncedXtream {
                    Button { use { await model.signIn(login); if case .failed(let message) = model.signIn { error = message } } } label: {
                        Text("Use \("IPTV"): \(URL(string: login.server)?.host() ?? login.server) · \(login.username)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
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
                        Text("Use \("Jellyfin"): \(URL(string: login.server)?.host() ?? login.server) · \(login.username)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("welcome.synced.jellyfin")
                }
                if let error = error ?? model.iCloudSignInError {
                    Text(verbatim: error).font(.footnote).foregroundStyle(TVTheme.warning)
                }
            }
            .disabled(working)
            .padding(.top, 24)
        }
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

/// The IPTV form: server, username, password (autofill), "Try the Demo".
struct IPTVSignInView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    static let demo = XtreamCredentials(server: "https://fernsy-demo.mobilistics.workers.dev", username: "demo", password: "demo")

    private var busy: Bool { model.signIn == .signingIn }

    var body: some View {
        Form {
            Section {
                TextField("Server Address", text: $server)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("signin.server")
                TextField("Username", text: $username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("signin.username")
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("signin.password")
            } footer: {
                Text("You find these details in your provider’s email under “Xtream Codes”. They are kept in the keychain.")
            }
            if case .failed(let message) = model.signIn {
                Text(message).foregroundStyle(TVTheme.warning).accessibilityIdentifier("signin.error")
            }
            Section {
                Button {
                    Task { await model.signIn(XtreamCredentials(server: server, username: username, password: password)) }
                } label: {
                    HStack { Text("Sign In"); if busy { Spacer(); ProgressView() } }
                }
                .disabled(server.isEmpty || username.isEmpty || password.isEmpty || busy)
                .accessibilityIdentifier("signin.submit")
                Button("Try the Demo") {
                    Task { await model.signIn(Self.demo) }
                }
                .disabled(busy)
                .accessibilityIdentifier("signin.demo")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Add IPTV Account")
        .onChange(of: model.signIn) { _, state in
            // Adding the account from Settings: back to the list once it is signed in.
            if state == .signedIn { dismiss() }
        }
    }
}

/// The Jellyfin form: server, username, password; signs in as on the Mac.
struct JellyfinSignInView: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Server Address", text: $server)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("jfsignin.server")
                TextField("Username", text: $username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("jfsignin.username")
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("jfsignin.password")
            } footer: {
                Text("The address of your Jellyfin server, for example http://192.168.1.20:8096, and your user. They are kept in the keychain.")
            }
            if let error {
                Text(verbatim: error).foregroundStyle(TVTheme.warning).accessibilityIdentifier("jfsignin.error")
            }
            Section {
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
                    HStack { Text("Sign In"); if busy { Spacer(); ProgressView() } }
                }
                .disabled(server.isEmpty || username.isEmpty || busy)
                .accessibilityIdentifier("jfsignin.submit")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Add Jellyfin Server")
    }
}

/// The launch screen while signing in with the logins in iCloud (icloud-auto-signin).
struct ICloudSignInView: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        VStack(spacing: 28) {
            Image("FernsyIcon").resizable().frame(width: 110, height: 110)
            Text("Signing in with your iCloud login").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.iCloudSteps) { step in
                    HStack(spacing: 14) {
                        ZStack {
                            if step.done {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(TVTheme.accentLight)
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: 26, height: 26)
                        ICloudSignInStepText(step: step)
                            .foregroundStyle(step.done ? TVTheme.text : TVTheme.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("icloud.step.\(step.kind.rawValue)")
                }
            }
            .frame(minHeight: 4 * 26 + 3 * 14, alignment: .top)
            .animation(.easeOut(duration: 0.3), value: model.iCloudSteps)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("icloud.signingIn")
    }
}

/// A step's words: what runs or what is done (the Apple TV screen's wording).
struct ICloudSignInStepText: View {
    let step: ICloudSignInStep

    var body: some View {
        words.contentTransition(.opacity)
    }

    private var words: Text {
        switch (step.kind, step.done) {
        case (.found, false): Text("Looking for your login in iCloud …")
        case (.found, true): Text("Login found in iCloud")
        case (.provider, false): Text("Signing in to \(step.server) …")
        case (.provider, true): Text("Signed in to \(step.server)")
        case (.channels, false): Text("Loading channels …")
        case (.channels, true): Text("Channels loaded")
        case (.jellyfin, false): Text("Signing in to Jellyfin \(step.server) …")
        case (.jellyfin, true): Text("Signed in to Jellyfin \(step.server)")
        }
    }
}

/// The shared model names the Apple TV form for the demo login (TVModel+Sync).
typealias IPTVSignInScreen = IPTVSignInView
