import FernsyCore
import FernsyPlayer
import SwiftUI

/// Settings (design screen `einstellungen`): accounts, adding one, playback languages, the
/// recordings' padding, the log and the version. No iCloud sync and no youth protection rows
/// (user decision 2026-10-26).
struct SettingsScreen: View {
    @EnvironmentObject private var model: TVModel
    @AppStorage(SyncStore.enabledKey) private var syncChoices = true
    @AppStorage(Recorder.padBeforeKey) private var padBefore = 10
    @AppStorage(Recorder.padAfterKey) private var padAfter = 10
    @AppStorage(TrackPreferences.audioKey) private var audioLanguage = ""
    @AppStorage(TrackPreferences.subtitlesKey) private var subtitles = "off"

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 90) {
                VStack(spacing: 24) {
                    Image("FernsyIcon").resizable().frame(width: 300, height: 300)
                    Text(verbatim: "Fernsy \(Self.version) · Apple TV")
                        .font(.system(size: 22)).foregroundStyle(TVTheme.text.opacity(0.55))
                        .accessibilityIdentifier("settings.version")
                }
                .frame(width: 620)
                .frame(maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header("ACCOUNTS")
                        if let credentials = model.credentials {
                            NavigationLink { AccountScreen() } label: {
                                SettingsRow(title: Text(verbatim: URL(string: credentials.server)?.host() ?? credentials.server),
                                            value: Text("IPTV"), dot: Color(hex: 0x4CD07D))
                            }
                            .accessibilityIdentifier("settings.account")
                        }
                        if let session = model.jellyfin.session {
                            NavigationLink { JellyfinAccountScreen() } label: {
                                SettingsRow(title: Text(verbatim: session.serverName), value: Text("Jellyfin"),
                                            dot: model.jellyfin.isOffline ? TVTheme.warning : Color(hex: 0x4CD07D))
                            }
                            .accessibilityIdentifier("settings.jellyfin")
                        }
                        NavigationLink { AddAccountScreen() } label: { SettingsRow(title: Text("Add Account")) }
                            .accessibilityIdentifier("settings.addAccount")
                        header("APP")
                        NavigationLink { PlaybackSettingsScreen() } label: {
                            SettingsRow(title: Text("Playback"), value: Text(playbackSummary))
                        }
                        .accessibilityIdentifier("settings.playback")
                        NavigationLink { RecordingSettingsScreen() } label: {
                            SettingsRow(title: Text("Recordings"), value: Text("Before \(padBefore) · After \(padAfter) min"))
                        }
                        .accessibilityIdentifier("settings.recordings")
                        NavigationLink { ICloudSettingsScreen() } label: {
                            SettingsRow(title: Text("iCloud"), value: Text(model.iCloudAvailable ? (syncChoices ? "On" : "Off") : "Not Available"))
                        }
                        .accessibilityIdentifier("settings.icloud")
                        NavigationLink { LogScreen() } label: { SettingsRow(title: Text("Log")) }
                            .accessibilityIdentifier("settings.log")
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(TVTileStyle(rest: .clear, radius: 16, scale: 1.03))
            }
            .padding(.leading, 90).padding(.trailing, 70)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TVTheme.background)
            .foregroundStyle(TVTheme.text)
        }
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

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold)).tracking(1.4)
            .foregroundStyle(TVTheme.text.opacity(0.5))
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 4)
    }
}

/// A settings row of the design: title, value and a chevron, light while focused.
struct SettingsRow: View {
    let title: Text
    var value: Text?
    var dot: Color?

    var body: some View {
        HStack(spacing: 16) {
            if let dot { Circle().fill(dot).frame(width: 12, height: 12) }
            title.fontWeight(.medium)
            Spacer()
            value?.opacity(0.6)
            Image(systemName: "chevron.right").opacity(0.4)
        }
        .font(.system(size: 26))
        .padding(.horizontal, 28)
        .frame(height: 76)
    }
}

/// A page under Settings: title and its content.
private struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(title).font(.system(size: 52, weight: .bold))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(.vertical, 10).padding(.horizontal, 20)
            }
            .buttonStyle(TVTileStyle(rest: .white.opacity(0.06), radius: 16, scale: 1.03))
        }
        .padding(.horizontal, 300)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TVTheme.background.ignoresSafeArea())
        .foregroundStyle(TVTheme.text)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct ChoiceRow: View {
    let title: Text
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                title
                Spacer()
                if chosen { Image(systemName: "checkmark") }
            }
            .font(.system(size: 26, weight: .medium))
            .padding(.horizontal, 28)
            .frame(height: 76)
        }
    }
}

private struct AccountScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var confirm = false

    var body: some View {
        SettingsPage(title: "IPTV Account") {
            if let credentials = model.credentials {
                SettingsRow(title: Text("Server"), value: Text(verbatim: credentials.server)).padding(.trailing, -40)
                SettingsRow(title: Text("Username"), value: Text(verbatim: credentials.username)).padding(.trailing, -40)
                SettingsRow(title: Text("Streams at a time"), value: Text(verbatim: "\(model.maxConnections)")).padding(.trailing, -40)
                ChoiceRow(title: Text("Movies"), chosen: model.showsIPTVMovies) { model.showsIPTVMovies.toggle() }
                    .accessibilityIdentifier("settings.iptvMovies")
                    .accessibilityValue(model.showsIPTVMovies ? "on" : "off")
                    .padding(.top, 24)
                ChoiceRow(title: Text("Series"), chosen: model.showsIPTVSeries) { model.showsIPTVSeries.toggle() }
                    .accessibilityIdentifier("settings.iptvSeries")
                    .accessibilityValue(model.showsIPTVSeries ? "on" : "off")
                Text("Sections that are switched off are not loaded or searched. Favorites and resume positions are kept.")
                    .font(.system(size: 22)).foregroundStyle(TVTheme.secondary).padding(.horizontal, 28).padding(.top, 20)
            }
            Button { confirm = true } label: {
                Text("Sign Out").font(.system(size: 26, weight: .semibold)).foregroundStyle(TVTheme.live)
                    .padding(.horizontal, 28).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            }
            .padding(.top, 30)
            .accessibilityIdentifier("settings.signOut")
        }
        .confirmationDialog("Sign out of this account?", isPresented: $confirm) {
            Button("Sign Out", role: .destructive) { model.signOut() }
        } message: {
            Text("Favorites, hidden channels and recordings stay on this Apple TV for when you sign in again.")
        }
    }
}

/// Offers the kind of account not yet signed in.
private struct AddAccountScreen: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        SettingsPage(title: "Add Account") {
            if model.credentials == nil {
                NavigationLink { IPTVSignInScreen() } label: { SettingsRow(title: Text("IPTV Account")) }
                    .accessibilityIdentifier("add.iptv")
            } else {
                SettingsRow(title: Text("IPTV Account"), value: Text("Signed in")).opacity(0.5).padding(.trailing, -40)
            }
            if model.jellyfin.session == nil {
                NavigationLink { JellyfinSignInScreen() } label: { SettingsRow(title: Text("Jellyfin Server")) }
                    .accessibilityIdentifier("add.jellyfin")
            } else {
                SettingsRow(title: Text("Jellyfin Server"), value: Text("Signed in")).opacity(0.5).padding(.trailing, -40)
            }
            Text("Fernsy uses one IPTV account and one Jellyfin server at a time; sign out to use another one.")
                .font(.system(size: 22)).foregroundStyle(TVTheme.secondary).padding(.horizontal, 28).padding(.top, 20)
        }
    }
}

private struct JellyfinAccountScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var confirm = false

    var body: some View {
        SettingsPage(title: "Jellyfin Server") {
            if let session = model.jellyfin.session {
                SettingsRow(title: Text("Server"), value: Text(verbatim: "\(session.serverName) · \(session.version)")).padding(.trailing, -40)
                SettingsRow(title: Text("Address"), value: Text(verbatim: session.server)).padding(.trailing, -40)
                SettingsRow(title: Text("User"), value: Text(verbatim: session.userName)).padding(.trailing, -40)
            }
            Button { confirm = true } label: {
                Text("Sign Out").font(.system(size: 26, weight: .semibold)).foregroundStyle(TVTheme.live)
                    .padding(.horizontal, 28).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            }
            .padding(.top, 30)
            .accessibilityIdentifier("settings.jellyfinSignOut")
        }
        .confirmationDialog("Sign out of this Jellyfin server?", isPresented: $confirm) {
            Button("Sign Out", role: .destructive) { model.jellyfin.signOut() }
        }
    }
}

private struct PlaybackSettingsScreen: View {
    @AppStorage(TrackPreferences.audioKey) private var audioLanguage = ""
    @AppStorage(TrackPreferences.subtitlesKey) private var subtitles = "off"
    @AppStorage(StreamInfoSetting.key) private var showStreamInfo = false

    var body: some View {
        SettingsPage(title: "Playback") {
            Text("AUDIO TRACK").font(.system(size: 20, weight: .bold)).tracking(1.4).opacity(0.5).padding(.horizontal, 28)
            ChoiceRow(title: Text("System Language"), chosen: audioLanguage.isEmpty) { audioLanguage = "" }
            ForEach(LanguageChoice.codes, id: \.self) { code in
                ChoiceRow(title: Text(verbatim: LanguageChoice.name(code)), chosen: audioLanguage == code) { audioLanguage = code }
            }
            Text("SUBTITLES").font(.system(size: 20, weight: .bold)).tracking(1.4).opacity(0.5).padding(.horizontal, 28).padding(.top, 24)
            ChoiceRow(title: Text("Off"), chosen: subtitles == "off") { subtitles = "off" }
            ChoiceRow(title: Text("Forced Only"), chosen: subtitles == "forced") { subtitles = "forced" }
            ForEach(LanguageChoice.codes, id: \.self) { code in
                ChoiceRow(title: Text(verbatim: LanguageChoice.name(code)), chosen: subtitles == code) { subtitles = code }
            }
            Text("Applies when playback starts, if the channel has the track.")
                .font(.system(size: 22)).foregroundStyle(TVTheme.secondary).padding(.horizontal, 28).padding(.top, 20)
            Text("PLAYER").font(.system(size: 20, weight: .bold)).tracking(1.4).opacity(0.5).padding(.horizontal, 28).padding(.top, 24)
            ChoiceRow(title: Text("Technical Info"), chosen: showStreamInfo) { showStreamInfo.toggle() }
                .accessibilityIdentifier("settings.streamInfo")
                .accessibilityValue(showStreamInfo ? "on" : "off")
            Text("Shows codec, decoder, buffer, reconnects and a buffer chart in the player, to look into stutters.")
                .font(.system(size: 22)).foregroundStyle(TVTheme.secondary).padding(.horizontal, 28).padding(.top, 20)
        }
    }
}

/// iCloud sync (icloud-sync): the two switches and whether iCloud is there.
private struct ICloudSettingsScreen: View {
    @EnvironmentObject private var model: TVModel
    @AppStorage(SyncStore.enabledKey) private var syncChoices = true
    @AppStorage(LoginSync.enabledKey) private var syncLogins = true

    var body: some View {
        SettingsPage(title: "iCloud") {
            if !model.iCloudAvailable {
                Text("iCloud is not available. Sign in to iCloud in the Apple TV’s settings; until then Fernsy keeps this Apple TV’s settings.")
                    .font(.system(size: 24)).foregroundStyle(TVTheme.warning).padding(.horizontal, 28).padding(.bottom, 20)
            }
            ChoiceRow(title: Text("Sync with iCloud"), chosen: syncChoices) { model.sync.isEnabled = !syncChoices; syncChoices.toggle() }
                .accessibilityIdentifier("settings.icloud.choices")
            Text("Hidden categories and channels, favorites, recently watched channels, where you stopped movies and episodes, audio and subtitle languages and recording padding, on your Macs and Apple TVs.")
                .font(.system(size: 22)).foregroundStyle(TVTheme.secondary).padding(.horizontal, 28).padding(.bottom, 20)
            ChoiceRow(title: Text("Sync Logins"), chosen: syncLogins) { syncLogins.toggle() }
                .accessibilityIdentifier("settings.icloud.logins")
            Text("Your provider’s and your Jellyfin server’s address, user and password, end-to-end encrypted in your iCloud. Another Mac or Apple TV offers them when it has no account yet; each signs in to Jellyfin as its own device.")
                .font(.system(size: 22)).foregroundStyle(TVTheme.secondary).padding(.horizontal, 28)
        }
        .task { await model.refreshSyncedLogins() }
    }
}

private struct RecordingSettingsScreen: View {
    @AppStorage(Recorder.padBeforeKey) private var padBefore = 10
    @AppStorage(Recorder.padAfterKey) private var padAfter = 10
    static let choices = [0, 2, 5, 10, 15, 30]

    var body: some View {
        SettingsPage(title: "Recordings") {
            Text("START EARLIER").font(.system(size: 20, weight: .bold)).tracking(1.4).opacity(0.5).padding(.horizontal, 28)
            HStack(spacing: 16) {
                ForEach(Self.choices, id: \.self) { minutes in
                    ChoiceRow(title: Text("\(minutes) min"), chosen: padBefore == minutes) { padBefore = minutes }
                        .accessibilityIdentifier("padBefore.\(minutes)")
                }
            }
            Text("END LATER").font(.system(size: 20, weight: .bold)).tracking(1.4).opacity(0.5).padding(.horizontal, 28).padding(.top, 24)
            HStack(spacing: 16) {
                ForEach(Self.choices, id: \.self) { minutes in
                    ChoiceRow(title: Text("\(minutes) min"), chosen: padAfter == minutes) { padAfter = minutes }
                        .accessibilityIdentifier("padAfter.\(minutes)")
                }
            }
            Text("Scheduled recordings follow the new times. Fernsy records only while it is open on this Apple TV.")
                .font(.system(size: 22)).foregroundStyle(TVTheme.secondary).padding(.horizontal, 28).padding(.top, 20)
        }
    }
}

/// The app log of this run, newest last.
private struct LogScreen: View {
    var body: some View {
        SettingsPage(title: "Log") {
            let entries = AppLog.shared.query(minimum: .info, query: "", limit: 400).entries
            ForEach(entries, id: \.id) { entry in
                Text(verbatim: entry.line)
                    .font(.system(size: 18).monospaced())
                    .foregroundStyle(entry.level == .error ? TVTheme.live : entry.level == .warning ? TVTheme.warning : TVTheme.text.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusable()
            }
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
