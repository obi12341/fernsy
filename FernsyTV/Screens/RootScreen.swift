import SwiftUI

/// The app's frame: the welcome screen and sign-in without an account, the tab bar with one.
/// Screens read only TVModel and keep the accessibility identifiers the UI tests use
/// (DEVELOPMENT.md › Apple TV).
struct RootScreen: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        Group {
            if model.signIn == .signedIn || !model.channels.isEmpty || model.jellyfin.session != nil {
                MainTabs()
            } else if model.signIn == .signingIn && model.startedWithAccount {
                ProgressView("Signing in …")
            } else {
                WelcomeScreen()
            }
        }
        .background(TVTheme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: Binding(get: { model.playing != nil || model.playingRecording != nil || model.playingVOD != nil },
                                              set: { if !$0 { model.stop() } })) {
            if model.playingRecording != nil { RecordingPlayerScreen() } else if model.playingVOD != nil { VODPlayerScreen() } else { PlayerScreen() }
        }
        .alert(model.question?.title ?? "", isPresented: Binding(get: { model.question != nil }, set: { if !$0 { model.question?.answer(false) } }),
               presenting: model.question) { question in
            Button(question.confirm) { question.answer(true) }
            Button(question.cancel, role: .cancel) { question.answer(false) }
        } message: { question in
            Text(verbatim: question.message)
        }
        .alert("Recording", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(verbatim: model.notice ?? "")
        }
    }
}

/// The top tab bar in the design's order; tabs whose source is not signed in are left out.
struct MainTabs: View {
    enum Tab: Hashable { case start, live, guide, films, series, jellyfin, recordings, search, settings }

    @EnvironmentObject private var model: TVModel
    @State private var selection: Tab = .start

    var body: some View {
        let iptv = model.credentials != nil || !model.channels.isEmpty
        let jellyfin = model.jellyfin.session != nil
        TabView(selection: $selection) {
            SwiftUI.Tab(value: Tab.start) { StartScreen() } label: { Text("Start") }
            if iptv {
                SwiftUI.Tab(value: Tab.live) { ChannelListScreen() } label: { Text("Live TV") }
                SwiftUI.Tab(value: Tab.guide) { GuideScreen() } label: { Text("Guide") }
                SwiftUI.Tab(value: Tab.films) { LibraryGridScreen(kind: .movies) } label: { Text("Films") }
                SwiftUI.Tab(value: Tab.series) { LibraryGridScreen(kind: .series) } label: { Text("Series") }
            }
            if jellyfin {
                SwiftUI.Tab(value: Tab.jellyfin) { JellyfinScreen() } label: { Text("Jellyfin") }
            }
            if iptv {
                SwiftUI.Tab(value: Tab.recordings) { RecordingsScreen() } label: { Text("Recordings") }
            }
            SwiftUI.Tab(value: Tab.search, role: .search) { SearchScreen() } label: {
                Label("Search", systemImage: "magnifyingglass").labelStyle(.iconOnly)
            }
            SwiftUI.Tab(value: Tab.settings) { SettingsScreen() } label: {
                Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
            }
        }
        .accessibilityIdentifier("tabs")
    }
}
