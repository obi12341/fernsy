import SwiftUI

enum AccountKind: String, CaseIterable, Identifiable {
    case iptv, jellyfin
    var id: String { rawValue }
}

struct LoginView: View {
    @State private var kind: AccountKind = .iptv

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("Fernsy").font(.largeTitle.weight(.semibold))
            Picker("Konto", selection: $kind) {
                Text("IPTV").tag(AccountKind.iptv)
                Text("Jellyfin").tag(AccountKind.jellyfin)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            switch kind {
            case .iptv: IPTVSignInForm()
            case .jellyfin: JellyfinSignInForm()
            }
        }
        .padding(48)
        .frame(minWidth: 600, minHeight: 600)
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
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Mit deinem Xtream-Codes-Zugang anmelden").foregroundStyle(.secondary)
            Form {
                TextField("Server", text: $server, prompt: Text("http://server:8080"))
                TextField("Benutzername", text: $username)
                SecureField("Passwort", text: $password)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 420, height: 150)
            .disabled(isWorking)
            .onSubmit(login)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(width: 400)
            }

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
                self.error = error.localizedDescription
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
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Mit deinem Jellyfin-Server verbinden").foregroundStyle(.secondary)
            Form {
                TextField("Server", text: $server, prompt: Text("https://jellyfin.example.com"))
                TextField("Benutzername", text: $username)
                SecureField("Passwort", text: $password)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 420, height: 150)
            .disabled(isWorking)
            .onSubmit(signIn)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(width: 400)
            }

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
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage(AppModel.timeshiftMinutesKey) private var timeshiftMinutes = 60
    @AppStorage(Recorder.padBeforeKey) private var padBefore = 10
    @AppStorage(Recorder.padAfterKey) private var padAfter = 10
    @AppStorage(MenuBarSupport.enabledKey) private var showsMenuBarItem = true
    @AppStorage(TrackPreferences.audioKey) private var audioLanguage = ""
    @AppStorage(TrackPreferences.subtitlesKey) private var subtitleMode = "off"

    @EnvironmentObject private var jellyfin: JellyfinStore
    @State private var addingAccount: AccountKind?

    var body: some View {
        Form {
            if app.credentials == nil {
                Section("IPTV") {
                    Button("IPTV-Konto hinzufügen …") { addingAccount = .iptv }
                }
            } else {
            Section("IPTV") {
                if let creds = app.credentials {
                    LabeledContent("Server", value: creds.server)
                    LabeledContent("Benutzer", value: creds.username)
                }
                if let expires = app.account?.expiresAt {
                    LabeledContent("Gültig bis", value: expires.formatted(date: .long, time: .omitted))
                }
                if let max = app.account?.maxConnections {
                    LabeledContent("Max. Verbindungen", value: String(max))
                }
                if let updated = app.lastUpdated {
                    LabeledContent("Katalog aktualisiert", value: updated.formatted(date: .abbreviated, time: .shortened))
                }
                HStack {
                    Button("Katalog aktualisieren") { Task { await app.loadCatalog(forceRefresh: true) } }
                        .disabled(app.isLoading)
                    Spacer()
                    Button("Abmelden", role: .destructive) { app.logout() }
                }
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
            Section("Inhalte") {
                Toggle("Erwachsenen-Kategorien anzeigen", isOn: $app.showAdult)
            }
            Section {
                Picker("Tonspur", selection: $audioLanguage) {
                    Text("Systemsprache (\(Self.languageName(Self.systemLanguage)))").tag("")
                    Divider()
                    ForEach(Self.languages, id: \.self) { code in Text(Self.languageName(code)).tag(code) }
                }
                Picker("Untertitel", selection: $subtitleMode) {
                    Text("Aus").tag("off")
                    Text("Nur erzwungene").tag("forced")
                    Divider()
                    ForEach(Self.languages, id: \.self) { code in Text(Self.languageName(code)).tag(code) }
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
                MinutesField("Vorlauf", value: $padBefore)
                MinutesField("Nachlauf", value: $padAfter)
                Toggle("Symbol in der Menüleiste", isOn: $showsMenuBarItem)
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
                Text("Zeitversetzt & Aufnahmen")
            } footer: {
                Text("Der Zwischenspeicher fürs Zurückspulen belegt bei HD-Sendern etwa 2–4 GB pro Stunde. Aufnahmen laufen nur, solange Fernsy geöffnet ist. Mit dem Symbol in der Menüleiste läuft Fernsy nach dem Schließen aller Fenster dort weiter; der Mac bleibt während Aufnahmen wach.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        .onChange(of: timeshiftMinutes) { _, _ in app.applyTimeshiftSetting() }
        .frame(width: 480)
        .padding(.vertical)
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
