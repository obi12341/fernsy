import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Fernsy").font(.largeTitle.weight(.semibold))
                Text("Mit deinem Xtream-Codes-Zugang anmelden").foregroundStyle(.secondary)
            }

            Form {
                TextField("Server", text: $server, prompt: Text("http://server:8080"))
                TextField("Benutzername", text: $username)
                SecureField("Passwort", text: $password)
            }
            .formStyle(.grouped)
            .frame(width: 420)
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
        .padding(48)
        .frame(minWidth: 600, minHeight: 560)
    }

    private func login() {
        guard !server.isEmpty, !username.isEmpty, !password.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        let creds = XtreamCredentials(server: server, username: username, password: password)
        Task {
            do {
                try await app.login(creds)
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

    var body: some View {
        Form {
            Section("Konto") {
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
            Section("Inhalte") {
                Toggle("Erwachsenen-Kategorien anzeigen", isOn: $app.showAdult)
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
        .onChange(of: timeshiftMinutes) { _, _ in app.applyTimeshiftSetting() }
        .frame(width: 480)
        .padding(.vertical)
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
