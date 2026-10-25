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
                Text("Willkommen bei Fernsy").font(.largeTitle.weight(.semibold))
                Text("Womit möchtest du dich verbinden?").foregroundStyle(.secondary)
            }
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
            Label("Fernsy sammelt keine Daten. Zugangsdaten bleiben im Schlüsselbund dieses Macs.", systemImage: "lock.fill")
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
                    Text(kind == .iptv ? "IPTV-Anbieter" : "Jellyfin-Server").font(.headline)
                    Text(kind == .iptv ? "Xtream Codes" : "Eigener Medienserver")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(kind == .iptv ? "Live-TV, Programm, Filme und Serien deines Anbieters" : "Filme und Serien von deinem eigenen Server")
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
                TextField("Benutzername", text: $username)
                Divider()
                SecureField("Passwort", text: $password)
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
                    Text("Anmelden").frame(width: 120)
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
                    Text("Anmelden").frame(width: 120)
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
    case accounts, playback, recordings, youthProtection, assistants
    var id: String { rawValue }
}

struct SettingsView: View {
    @State private var tab: SettingsTab = Self.initialTab

    var body: some View {
        TabView(selection: $tab) {
            AccountsSettings()
                .tabItem { Label("Konten", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            PlaybackSettings()
                .tabItem { Label("Wiedergabe", systemImage: "play.rectangle") }
                .tag(SettingsTab.playback)
            RecordingSettings()
                .tabItem { Label("Aufnahmen", systemImage: "record.circle") }
                .tag(SettingsTab.recordings)
            YouthProtectionSettings()
                .tabItem { Label("Jugendschutz", systemImage: "hand.raised") }
                .tag(SettingsTab.youthProtection)
            AssistantSettings()
                .tabItem { Label("Assistenten", systemImage: "bubble.left.and.text.bubble.right") }
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
                    LabeledContent("Benutzer", value: creds.username)
                    if let expires = app.account?.expiresAt {
                        LabeledContent("Gültig bis", value: expires.formatted(date: .long, time: .omitted))
                    }
                    if let max = app.account?.maxConnections {
                        LabeledContent("Max. Verbindungen", value: String(max))
                    }
                    if let updated = app.lastUpdated {
                        LabeledContent("Katalog aktualisiert", value: updated.formatted(date: .abbreviated, time: .shortened))
                    }
                    Toggle("Filme", isOn: $app.showsIPTVMovies)
                    Toggle("Serien", isOn: $app.showsIPTVSeries)
                    HStack {
                        Button("Katalog aktualisieren") { Task { await app.loadCatalog(forceRefresh: true) } }
                            .disabled(app.isLoading)
                        Spacer()
                        Button("Abmelden", role: .destructive) { app.logout() }
                    }
                } else {
                    Button("IPTV-Konto hinzufügen …") { addingAccount = .iptv }
                }
            } header: {
                Text("IPTV")
            } footer: {
                if app.credentials != nil {
                    Text("Ausgeschaltete Bereiche werden nicht geladen und nicht durchsucht. Favoriten und Fortsetzen-Positionen bleiben erhalten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Jellyfin") {
                if let session = jellyfin.session {
                    LabeledContent("Server", value: "\(session.serverName) (Jellyfin \(session.version))")
                    LabeledContent("Adresse", value: session.server)
                    LabeledContent("Benutzer", value: session.userName)
                    if jellyfin.isExpired {
                        Text("Die Sitzung ist abgelaufen.").foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Bibliothek aktualisieren") { Task { await jellyfin.loadLibrary(forceRefresh: true) } }
                            .disabled(jellyfin.isLoading)
                        if jellyfin.isExpired {
                            Button("Neu anmelden …") { addingAccount = .jellyfin }
                        }
                        Spacer()
                        Button("Abmelden", role: .destructive) { jellyfin.signOut() }
                    }
                } else {
                    Button("Jellyfin-Server hinzufügen …") { addingAccount = .jellyfin }
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
                Button("Abbrechen") { addingAccount = nil }.keyboardShortcut(.cancelAction)
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
                Picker("Tonspur", selection: $audioLanguage) {
                    Text("Systemsprache (\(SettingsView.languageName(SettingsView.systemLanguage)))").tag("")
                    Divider()
                    ForEach(SettingsView.languages, id: \.self) { code in Text(SettingsView.languageName(code)).tag(code) }
                }
                Picker("Untertitel", selection: $subtitleMode) {
                    Text("Aus").tag("off")
                    Text("Nur erzwungene").tag("forced")
                    Divider()
                    ForEach(SettingsView.languages, id: \.self) { code in Text(SettingsView.languageName(code)).tag(code) }
                }
            } header: {
                Text("Sprache & Untertitel")
            } footer: {
                Text("Gilt beim Start jeder Wiedergabe, wenn die Spur vorhanden ist. „Nur erzwungene“ zeigt Untertitel nur für fremdsprachige Stellen. Wählst du im Player andere Spuren für eine Serienfolge, merkt sich Fernsy das für die weiteren Folgen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Zurückspulen bis", selection: $timeshiftMinutes) {
                    Text("2 Minuten").tag(2)
                    Text("15 Minuten").tag(15)
                    Text("30 Minuten").tag(30)
                    Text("1 Stunde").tag(60)
                    Text("2 Stunden").tag(120)
                }
            } header: {
                Text("Zeitversetzt")
            } footer: {
                Text("Der Zwischenspeicher fürs Zurückspulen belegt bei HD-Sendern etwa 2–4 GB pro Stunde.")
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
                MinutesField("Vorlauf", value: $padBefore)
                MinutesField("Nachlauf", value: $padAfter)
                LabeledContent("Speicherort") {
                    HStack {
                        Text("Filme › Fernsy").foregroundStyle(.secondary)
                        Button("Im Finder zeigen") {
                            try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(Recorder.folder)
                        }
                    }
                }
            } header: {
                Text("Aufnahmen")
            } footer: {
                Text("Aufnahmen laufen nur, solange Fernsy geöffnet ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Mac wach halten", selection: $keepAwakeHours) {
                    ForEach(Recorder.keepAwakeChoices, id: \.self) { hours in
                        Text(Self.keepAwakeLabel(hours)).tag(hours)
                    }
                }
            } footer: {
                Text(keepAwakeHours < 0
                     ? "Fernsy hält den Mac nicht wach. Geht er in den Ruhezustand, bricht eine laufende Aufnahme ab."
                     : "Der Mac geht während Aufnahmen und vor geplanten Aufnahmen nicht von selbst in den Ruhezustand. Zuklappen im Akkubetrieb oder „Ruhezustand“ im Apple-Menü verhindert das nicht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Symbol in der Menüleiste", isOn: $showsMenuBarItem)
                Toggle("Beim Anmelden öffnen", isOn: Binding(
                    get: { loginItem.status != .off },
                    set: { loginItem.setEnabled($0) }))
                if loginItem.status == .requiresApproval {
                    LabeledContent {
                        Button("Anmeldeobjekte öffnen …") { loginItem.openSystemSettings() }
                    } label: {
                        Text("macOS muss das Öffnen beim Anmelden noch erlauben.")
                            .foregroundStyle(.orange)
                    }
                }
            } footer: {
                Text("Mit dem Symbol in der Menüleiste läuft Fernsy nach dem Schließen aller Fenster dort weiter. Beim Anmelden geöffnet, startet Fernsy ohne Fenster, damit geplante Aufnahmen stattfinden.")
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
        case ..<0: "Aus"
        case 0: "Immer, solange eine Aufnahme geplant ist"
        case 1: "1 Stunde vor einer Aufnahme"
        default: "\(hours) Stunden vor einer Aufnahme"
        }
    }
}

private struct YouthProtectionSettings: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let detected: [(section: LocalizedStringKey, category: XCategory)] =
            app.liveCategories.filter(app.isAdultCategory).map { ("Live-TV", $0) }
            + app.movieCategories.filter(app.isAdultCategory).map { ("Filme", $0) }
            + app.seriesCategories.filter(app.isAdultCategory).map { ("Serien", $0) }
        Form {
            Section {
                Toggle("Erwachsenen-Kategorien anzeigen", isOn: $app.showAdult)
                Toggle("Erwachsenen-Sender unter „Zuletzt gesehen“ anzeigen", isOn: $app.showAdultInRecent)
                    .disabled(!app.showAdult)
            } footer: {
                Text("Fernsy erkennt Erwachsenen-Kategorien am Namen und blendet sie samt ihren Inhalten aus. Das ist keine Kindersicherung. Unter „Zuletzt gesehen“ erscheinen Erwachsenen-Sender nur, wenn beides eingeschaltet ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                if detected.isEmpty {
                    Text("Keine erkannt").foregroundStyle(.secondary)
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
                Text("Erkannte Kategorien (\(detected.count))")
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
                Toggle("MCP-Server", isOn: $mcp.isEnabled)
                LabeledContent("Status") { statusText }
                LabeledContent("Adresse") { Text(verbatim: MCPServer.endpoint).textSelection(.enabled) }
                LabeledContent("Zugangsschlüssel") {
                    HStack {
                        Button("Kopieren") { copy(mcp.token) }
                        Button("Neu erzeugen") { mcp.regenerateToken() }
                    }
                }
            } footer: {
                Text("Claude und andere Assistenten können das Programm, den Verlauf und Fernsys Protokoll lesen (ohne Zugangsdaten), Aufnahmen planen und Sendungen abspielen. Nur Programme auf diesem Mac mit dem Zugangsschlüssel können sich verbinden, und nur solange Fernsy geöffnet ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    Button("Befehl kopieren") { copy(claudeCode) }
                } label: {
                    Text("Im Terminal ausführen")
                }
            } header: {
                Text(verbatim: "Claude Code")
            }
            Section {
                LabeledContent {
                    Button("Zu Claude Desktop hinzufügen …") { MCPDesktopExtension.addToClaude(token: mcp.token) }
                } label: {
                    Text("Als Erweiterung installieren")
                }
                LabeledContent {
                    Button("Eintrag kopieren") { copy(claudeDesktop) }
                } label: {
                    Text("Manuell einrichten")
                }
            } header: {
                Text(verbatim: "Claude Desktop")
            } footer: {
                Text("Claude Desktop zeigt einen Installationsdialog; danach kann Claude Fernsy nutzen. Nach „Neu erzeugen“ füge Fernsy erneut hinzu. Manuell: den Eintrag unter „mcpServers“ in claude_desktop_config.json einfügen (braucht Node.js).")
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
        case .off: Text("Aus").foregroundStyle(.secondary)
        case .starting: Text("Startet …").foregroundStyle(.secondary)
        case .running: Text("Bereit").foregroundStyle(.green)
        case .failed(let message): Text("Fehler: \(message)").foregroundStyle(.red)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
