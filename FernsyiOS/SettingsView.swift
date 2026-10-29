import FernsyCore
import FernsyPlayer
import SwiftUI

/// Settings (ios-app "Settings"): accounts, adding one, the IPTV films and series switches,
/// playback, iCloud, the log and the version. No recording settings on iPhone and iPad.
struct SettingsView: View {
    @EnvironmentObject private var model: TVModel
    @AppStorage(SyncStore.enabledKey) private var syncChoices = true
    @AppStorage(TrackPreferences.audioKey) private var audioLanguage = ""
    @AppStorage(TrackPreferences.subtitlesKey) private var subtitles = "off"

    var body: some View {
        Form {
            Section("Accounts") {
                if let credentials = model.credentials {
                    NavigationLink { AccountView() } label: {
                        row(Text(verbatim: URL(string: credentials.server)?.host() ?? credentials.server), Text("IPTV"), dot: Color(hex: 0x4CD07D))
                    }
                    .accessibilityIdentifier("settings.account")
                }
                if let session = model.jellyfin.session {
                    NavigationLink { JellyfinAccountView() } label: {
                        row(Text(verbatim: session.serverName), Text("Jellyfin"), dot: model.jellyfin.isOffline ? TVTheme.warning : Color(hex: 0x4CD07D))
                    }
                    .accessibilityIdentifier("settings.jellyfin")
                }
                if model.credentials == nil {
                    NavigationLink("Add IPTV Account") { IPTVSignInView() }.accessibilityIdentifier("add.iptv")
                }
                if model.jellyfin.session == nil {
                    NavigationLink("Add Jellyfin Server") { JellyfinSignInView() }.accessibilityIdentifier("add.jellyfin")
                }
            }
            Section("App") {
                NavigationLink { PlaybackSettingsView() } label: { row(Text("Playback"), Text(playbackSummary)) }
                    .accessibilityIdentifier("settings.playback")
                NavigationLink { ICloudSettingsView() } label: {
                    row(Text("iCloud"), Text(model.iCloudAvailable ? (syncChoices ? "On" : "Off") : "Not Available"))
                }
                .accessibilityIdentifier("settings.icloud")
                NavigationLink("Log") { LogView() }.accessibilityIdentifier("settings.log")
            }
            Section {
                HStack(spacing: 12) {
                    Image("FernsyIcon").resizable().frame(width: 40, height: 40)
                    Text(verbatim: "Fernsy \(Self.version)").foregroundStyle(TVTheme.secondary)
                        .accessibilityIdentifier("settings.version")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var playbackSummary: String {
        let audio = audioLanguage.isEmpty ? String(localized: "System language") : LanguageChoice.name(audioLanguage)
        let subs: String = switch subtitles {
        case "off": String(localized: "subtitles off")
        case "forced": String(localized: "forced subtitles")
        default: String(localized: "subtitles \(LanguageChoice.name(subtitles))")
        }
        return "\(audio) · \(subs)"
    }

    private func row(_ title: Text, _ value: Text, dot: Color? = nil) -> some View {
        HStack {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            title
            Spacer()
            value.foregroundStyle(TVTheme.tertiary).lineLimit(1)
        }
    }
}

/// The languages offered for audio and subtitles.
enum LanguageChoice {
    static let codes = ["de", "en", "fr", "es", "it", "tr", "pl", "nl"]

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
    }
}

private struct AccountView: View {
    @EnvironmentObject private var model: TVModel
    @State private var confirm = false

    var body: some View {
        Form {
            if let credentials = model.credentials {
                Section {
                    LabeledContent("Server", value: credentials.server)
                    LabeledContent("Username", value: credentials.username)
                    LabeledContent("Streams at a time", value: "\(model.maxConnections)")
                }
                Section {
                    Toggle("Movies", isOn: $model.showsIPTVMovies).accessibilityIdentifier("settings.iptvMovies")
                    Toggle("Series", isOn: $model.showsIPTVSeries).accessibilityIdentifier("settings.iptvSeries")
                } footer: {
                    Text("Sections that are switched off are not loaded or searched. Favorites and resume positions are kept.")
                }
            }
            Section {
                Button("Sign Out", role: .destructive) { confirm = true }.accessibilityIdentifier("settings.signOut")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("IPTV Account")
        .confirmationDialog("Sign out of this account?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { model.signOut() }
        } message: {
            Text("Favorites and hidden channels stay on this device for when you sign in again.")
        }
    }
}

private struct JellyfinAccountView: View {
    @EnvironmentObject private var model: TVModel
    @State private var confirm = false

    var body: some View {
        Form {
            if let session = model.jellyfin.session {
                Section {
                    LabeledContent("Server", value: "\(session.serverName) · \(session.version)")
                    LabeledContent("Address", value: session.server)
                    LabeledContent("User", value: session.userName)
                }
            }
            Section {
                Button("Sign Out", role: .destructive) { confirm = true }.accessibilityIdentifier("settings.jellyfinSignOut")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Jellyfin Server")
        .confirmationDialog("Sign out of this Jellyfin server?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { model.jellyfin.signOut() }
        }
    }
}

private struct PlaybackSettingsView: View {
    @AppStorage(TrackPreferences.audioKey) private var audioLanguage = ""
    @AppStorage(TrackPreferences.subtitlesKey) private var subtitles = "off"
    @AppStorage(StreamInfoSetting.key) private var showStreamInfo = false

    var body: some View {
        Form {
            Section {
                Picker("Audio Track", selection: $audioLanguage) {
                    Text("System Language").tag("")
                    ForEach(LanguageChoice.codes, id: \.self) { code in Text(verbatim: LanguageChoice.name(code)).tag(code) }
                }
                Picker("Subtitles", selection: $subtitles) {
                    Text("Off").tag("off")
                    Text("Forced Only").tag("forced")
                    ForEach(LanguageChoice.codes, id: \.self) { code in Text(verbatim: LanguageChoice.name(code)).tag(code) }
                }
            } footer: {
                Text("Applies when playback starts, if the channel has the track.")
            }
            Section {
                Toggle("Technical Info", isOn: $showStreamInfo).accessibilityIdentifier("settings.streamInfo")
            } footer: {
                Text("Shows codec, decoder, buffer, reconnects and a buffer chart in the player, to look into stutters.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Playback")
    }
}

/// iCloud sync (icloud-sync): the two switches and whether iCloud is there.
private struct ICloudSettingsView: View {
    @EnvironmentObject private var model: TVModel
    @AppStorage(SyncStore.enabledKey) private var syncChoices = true
    @AppStorage(LoginSync.enabledKey) private var syncLogins = true

    var body: some View {
        Form {
            if !model.iCloudAvailable {
                Text("iCloud is not available. Sign in to iCloud in the device’s settings; until then Fernsy keeps this device’s settings.")
                    .foregroundStyle(TVTheme.warning)
            }
            Section {
                Toggle("Sync with iCloud", isOn: Binding(get: { syncChoices }, set: { model.sync.isEnabled = $0; syncChoices = $0 }))
                    .accessibilityIdentifier("settings.icloud.choices")
            } footer: {
                Text("Hidden categories and channels, favorites, recently watched channels, where you stopped movies and episodes, and audio and subtitle languages, on all your devices.")
            }
            Section {
                Toggle("Sync Logins", isOn: $syncLogins).accessibilityIdentifier("settings.icloud.logins")
            } footer: {
                Text("Your provider’s and your Jellyfin server’s address, user and password, end-to-end encrypted in your iCloud. Another device offers them when it has no account yet.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("iCloud")
        .task { await model.refreshSyncedLogins() }
    }
}

/// The app log of this run, newest last.
private struct LogView: View {
    var body: some View {
        let entries = AppLog.shared.query(minimum: .info, query: "", limit: 400).entries
        List(entries, id: \.id) { entry in
            Text(verbatim: entry.line)
                .font(.caption.monospaced())
                .foregroundStyle(entry.level == .error ? TVTheme.live : entry.level == .warning ? TVTheme.warning : TVTheme.text.opacity(0.8))
                .textSelection(.enabled)
        }
        .listStyle(.plain)
        .navigationTitle("Log")
    }
}
