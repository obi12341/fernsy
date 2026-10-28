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
                if let error {
                    Label(error.localizedDescription, systemImage: "exclamationmark.circle.fill")
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
                    Text(kind == .iptv ? "Live TV, guide, films and series from your provider" : "Films and series from your own server")
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

enum SettingsTab: String, CaseIterable, Identifiable {
    case accounts, playback, recordings, icloud, youthProtection, assistants
    var id: String { rawValue }
}

struct SettingsView: View {
    @State private var tab: SettingsTab = Self.initialTab

    var body: some View {
        TabView(selection: $tab) {
            AccountsSettings()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }
                .tag(SettingsTab.playback)
            RecordingSettings()
                .tabItem { Label("Recordings", systemImage: "record.circle") }
                .tag(SettingsTab.recordings)
            ICloudSettings()
                .tabItem { Label("iCloud", systemImage: "icloud") }
                .tag(SettingsTab.icloud)
            YouthProtectionSettings()
                .tabItem { Label("Youth Protection", systemImage: "hand.raised") }
                .tag(SettingsTab.youthProtection)
            AssistantSettings()
                .tabItem { Label("Assistants", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(SettingsTab.assistants)
        }
        .frame(width: 560)
    }

    /// IPTV_TESTSETTINGS=<tab> (DEBUG) opens Settings on that tab.
    private static var initialTab: SettingsTab {
        #if DEBUG
        if let tab = ProcessInfo.processInfo.environment["IPTV_TESTSETTINGS"].flatMap(SettingsTab.init) { return tab }
        #endif
        return .accounts
    }
}

private struct AccountsSettings: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var jellyfin: JellyfinStore
    @State private var addingAccount: AccountKind?

    var body: some View {
        Form {
            Section {
                if let creds = app.credentials {
                    LabeledContent("Server", value: creds.server)
                    LabeledContent("User", value: creds.username)
                    if let expires = app.account?.expiresAt {
                        LabeledContent("Valid until", value: expires.formatted(date: .long, time: .omitted))
                    }
                    if let max = app.account?.maxConnections {
                        LabeledContent("Max. connections", value: String(max))
                    }
                    if let updated = app.lastUpdated {
                        LabeledContent("Catalog updated", value: updated.formatted(date: .abbreviated, time: .shortened))
                    }
                    Toggle("Movies", isOn: $app.showsIPTVMovies)
                    Toggle("Series", isOn: $app.showsIPTVSeries)
                    HStack {
                        Button("Refresh Catalog") { Task { await app.loadCatalog(forceRefresh: true) } }
                            .disabled(app.isLoading)
                        Spacer()
                        Button("Sign Out", role: .destructive) { app.logout() }
                    }
                } else {
                    Button("Add IPTV Account …") { addingAccount = .iptv }
                }
            } header: {
                Text("IPTV")
            } footer: {
                if app.credentials != nil {
                    Text("Sections that are switched off are not loaded or searched. Favorites and resume positions are kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Jellyfin") {
                if let session = jellyfin.session {
                    LabeledContent("Server", value: "\(session.serverName) (Jellyfin \(session.version))")
                    LabeledContent("Address", value: session.server)
                    LabeledContent("User", value: session.userName)
                    if jellyfin.isExpired {
                        Text("The session has expired.").foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Refresh Library") { Task { await jellyfin.loadLibrary(forceRefresh: true) } }
                            .disabled(jellyfin.isLoading)
                        if jellyfin.isExpired {
                            Button("Sign In Again …") { addingAccount = .jellyfin }
                        }
                        Spacer()
                        Button("Sign Out", role: .destructive) { jellyfin.signOut() }
                    }
                } else {
                    Button("Add Jellyfin Server …") { addingAccount = .jellyfin }
                }
            }
            #if DIRECT_DISTRIBUTION
            UpdateSettingsSection(updater: app.updater)
            #endif
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $addingAccount) { kind in
            VStack {
                switch kind {
                case .iptv: IPTVSignInForm { addingAccount = nil }
                case .jellyfin:
                    JellyfinSignInForm(prefillServer: jellyfin.session?.server, prefillUser: jellyfin.session?.userName) { addingAccount = nil }
                }
                Button("Cancel") { addingAccount = nil }.keyboardShortcut(.cancelAction)
            }
            .padding(28)
        }
    }
}

private struct PlaybackSettings: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage(AppModel.timeshiftMinutesKey) private var timeshiftMinutes = 60
    @AppStorage(TrackPreferences.audioKey) private var audioLanguage = ""
    @AppStorage(TrackPreferences.subtitlesKey) private var subtitleMode = "off"

    var body: some View {
        Form {
            Section {
                Picker("Audio Track", selection: $audioLanguage) {
                    Text("System Language (\(SettingsView.languageName(SettingsView.systemLanguage)))").tag("")
                    Divider()
                    ForEach(SettingsView.languages, id: \.self) { code in Text(SettingsView.languageName(code)).tag(code) }
                }
                Picker("Subtitles", selection: $subtitleMode) {
                    Text("Off").tag("off")
                    Text("Forced Only").tag("forced")
                    Divider()
                    ForEach(SettingsView.languages, id: \.self) { code in Text(SettingsView.languageName(code)).tag(code) }
                }
            } header: {
                Text("Language & Subtitles")
            } footer: {
                Text("Applies when playback starts, if the track exists. “Forced only” shows subtitles only for foreign-language passages. If you pick other tracks in the player during a series episode, Fernsy keeps them for the following episodes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Rewind up to", selection: $timeshiftMinutes) {
                    Text("2 minutes").tag(2)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
            } header: {
                Text("Time Shift")
            } footer: {
                Text("The rewind buffer takes about 2–4 GB per hour for HD channels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: timeshiftMinutes) { _, _ in app.applyTimeshiftSetting() }
    }
}

private struct RecordingSettings: View {
    @AppStorage(Recorder.padBeforeKey) private var padBefore = 10
    @AppStorage(Recorder.padAfterKey) private var padAfter = 10
    @AppStorage(MenuBarSupport.enabledKey) private var showsMenuBarItem = true
    @AppStorage(Recorder.keepAwakeHoursKey) private var keepAwakeHours = 6
    @StateObject private var loginItem = LoginItem()

    var body: some View {
        Form {
            Section {
                MinutesField("Record before", value: $padBefore)
                MinutesField("Record after", value: $padAfter)
                LabeledContent("Location") {
                    HStack {
                        Text("Movies › Fernsy").foregroundStyle(.secondary)
                        Button("Show in Finder") {
                            try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(Recorder.folder)
                        }
                    }
                }
            } header: {
                Text("Recordings")
            } footer: {
                Text("Recordings only run while Fernsy is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Keep Mac awake", selection: $keepAwakeHours) {
                    ForEach(Recorder.keepAwakeChoices, id: \.self) { hours in
                        Text(Self.keepAwakeLabel(hours)).tag(hours)
                    }
                }
            } footer: {
                Text(keepAwakeHours < 0
                     ? "Fernsy does not keep the Mac awake. If it goes to sleep, a running recording stops."
                     : "The Mac does not go to sleep on its own during recordings and before scheduled ones. This does not prevent closing the lid on battery or choosing Sleep in the Apple menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show in menu bar", isOn: $showsMenuBarItem)
                Toggle("Open at Login", isOn: Binding(
                    get: { loginItem.status != .off },
                    set: { loginItem.setEnabled($0) }))
                if loginItem.status == .requiresApproval {
                    LabeledContent {
                        Button("Open Login Items …") { loginItem.openSystemSettings() }
                    } label: {
                        Text("macOS still has to allow opening at login.")
                            .foregroundStyle(.orange)
                    }
                }
            } footer: {
                Text("With the menu bar icon, Fernsy keeps running there after you close all windows. Opened at login, Fernsy starts without a window so that scheduled recordings happen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}

extension RecordingSettings {
    static func keepAwakeLabel(_ hours: Int) -> LocalizedStringKey {
        switch hours {
        case ..<0: "Off"
        case 0: "Always while a recording is scheduled"
        case 1: "1 hour before a recording"
        default: "\(hours) hours before a recording"
        }
    }
}

/// iCloud sync (icloud-sync): the two switches and whether iCloud is there.
private struct ICloudSettings: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage(SyncStore.enabledKey) private var syncChoices = true
    @AppStorage(LoginSync.enabledKey) private var syncLogins = true

    var body: some View {
        Form {
            Section {
                Toggle("Sync with iCloud", isOn: Binding(get: { syncChoices }, set: { app.sync.isEnabled = $0; syncChoices = $0 }))
                Text("Hidden categories and channels, favourites, recently watched channels, where you stopped films and episodes, audio and subtitle languages and recording padding, on your Macs and Apple TVs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Sync Logins", isOn: $syncLogins)
                Text("Your provider’s and your Jellyfin server’s address, user and password, end-to-end encrypted in your iCloud. Another Mac or Apple TV offers them when it has no account yet; each signs in to Jellyfin as its own device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !app.iCloudAvailable {
                Section {
                    Label("iCloud is not available. Sign in to iCloud in System Settings; until then Fernsy keeps this Mac’s settings.", systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await app.refreshSyncedLogins() }
    }
}

private struct YouthProtectionSettings: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let detected: [(section: LocalizedStringKey, category: XCategory)] =
            app.liveCategories.filter(app.isAdultCategory).map { ("Live TV", $0) }
            + app.movieCategories.filter(app.isAdultCategory).map { ("Movies", $0) }
            + app.seriesCategories.filter(app.isAdultCategory).map { ("Series", $0) }
        Form {
            Section {
                Toggle("Show adult categories", isOn: $app.showAdult)
                Toggle("Show adult channels in Recently Watched", isOn: $app.showAdultInRecent)
                    .disabled(!app.showAdult)
            } footer: {
                Text("Fernsy detects adult categories by their name and hides them along with their content. This is not a parental lock. Adult channels appear in Recently Watched only when both are on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                if detected.isEmpty {
                    Text("None detected").foregroundStyle(.secondary)
                } else {
                    ForEach(detected.indices, id: \.self) { i in
                        LabeledContent {
                            Text(verbatim: detected[i].category.name)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } label: {
                            Text(detected[i].section)
                        }
                    }
                }
            } header: {
                Text("Detected categories (\(detected.count))")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(detected.count < 8)
        .frame(height: detected.count < 8 ? nil : 460)
        .fixedSize(horizontal: false, vertical: detected.count < 8)
    }
}

extension SettingsView {
    /// Languages offered for audio and subtitles, sorted by their name in the UI language.
    static let languages: [String] = ["ar", "cs", "da", "de", "el", "en", "es", "fi", "fr", "he", "hu", "it", "ja",
                                      "ko", "nb", "nl", "pl", "pt", "ro", "ru", "sv", "tr", "uk", "zh"]
        .sorted { languageName($0).localizedCompare(languageName($1)) == .orderedAscending }

    static var systemLanguage: String {
        Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier(.alpha2) } ?? "de"
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }
}

/// Whole minutes 0…60 as a number field with a stepper; values outside are clamped.
private struct MinutesField: View {
    let label: LocalizedStringKey
    @Binding var value: Int

    init(_ label: LocalizedStringKey, value: Binding<Int>) {
        self.label = label
        _value = value
    }

    static func clamp(_ minutes: Int) -> Int { min(60, max(0, minutes)) }

    var body: some View {
        let clamped = Binding(get: { value }, set: { value = Self.clamp($0) })
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("", value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                Text("min").foregroundStyle(.secondary)
                Stepper("", value: clamped, in: 0...60).labelsHidden()
            }
        }
    }
}

/// Settings › Assistenten: the local MCP server for Claude and other assistants.
private struct AssistantSettings: View {
    @EnvironmentObject private var app: AppModel

    var body: some View { MCPSettingsForm(mcp: app.mcp) }
}

private struct MCPSettingsForm: View {
    @ObservedObject var mcp: MCPServer

    private var claudeCode: String {
        "claude mcp add --transport http fernsy \(MCPServer.endpoint) --header \"Authorization: Bearer \(mcp.token)\""
    }

    private var claudeDesktop: String {
        """
        "fernsy": {
          "command": "npx",
          "args": ["-y", "mcp-remote", "\(MCPServer.endpoint)", "--header", "Authorization: Bearer \(mcp.token)", "--transport", "http-only"]
        }
        """
    }

    var body: some View {
        Form {
            Section {
                Toggle("MCP Server", isOn: $mcp.isEnabled)
                LabeledContent("Status") { statusText }
                LabeledContent("Address") { Text(verbatim: MCPServer.endpoint).textSelection(.enabled) }
                LabeledContent("Access Token") {
                    HStack {
                        Button("Copy") { copy(mcp.token) }
                        Button("Regenerate") { mcp.regenerateToken() }
                    }
                }
            } footer: {
                Text("Claude and other assistants can read the guide, your history and Fernsy's log (without credentials), schedule recordings and play shows. Only programs on this Mac with the access token can connect, and only while Fernsy is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    Button("Copy Command") { copy(claudeCode) }
                } label: {
                    Text("Run in Terminal")
                }
            } header: {
                Text(verbatim: "Claude Code")
            }
            Section {
                LabeledContent {
                    Button("Add to Claude Desktop …") { MCPDesktopExtension.addToClaude(token: mcp.token) }
                } label: {
                    Text("Install as an extension")
                }
                LabeledContent {
                    Button("Copy Entry") { copy(claudeDesktop) }
                } label: {
                    Text("Set up manually")
                }
            } header: {
                Text(verbatim: "Claude Desktop")
            } footer: {
                Text("Claude Desktop shows an install dialog; after that, Claude can use Fernsy. After \"Regenerate\", add Fernsy again. Manually: paste the entry under \"mcpServers\" in claude_desktop_config.json (needs Node.js).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusText: some View {
        switch mcp.status {
        case .off: Text("Off").foregroundStyle(.secondary)
        case .starting: Text("Starting …").foregroundStyle(.secondary)
        case .running: Text("Ready").foregroundStyle(.green)
        case .failed(let message): Text("Error: \(message)").foregroundStyle(.red)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
