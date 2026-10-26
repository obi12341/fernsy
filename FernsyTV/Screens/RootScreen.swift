import SwiftUI

/// The app's frame: the welcome screen and sign-in without an account, the tab bar with one.
/// Screens read only TVModel and keep the accessibility identifiers the UI tests use
/// (DEVELOPMENT.md › Apple TV).
struct RootScreen: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        Group {
            if model.signIn == .signedIn || !model.channels.isEmpty {
                MainTabs()
            } else if model.signIn == .signingIn && model.startedWithAccount {
                ProgressView("Signing in …")
            } else {
                WelcomeScreen()
            }
        }
        .background(TVTheme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: Binding(get: { model.playing != nil || model.playingRecording != nil },
                                              set: { if !$0 { model.stop() } })) {
            if model.playingRecording != nil { RecordingPlayerScreen() } else { PlayerScreen() }
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

/// The top tab bar (design F of tvos-live): Live TV, Programm, Aufnahmen and the gear.
struct MainTabs: View {
    enum Tab: Hashable { case live, guide, recordings, settings }

    @State private var selection: Tab = .live

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab(value: Tab.live) { ChannelListScreen() } label: { Text("Live TV") }
            SwiftUI.Tab(value: Tab.guide) { GuideScreen() } label: { Text("Guide") }
            SwiftUI.Tab(value: Tab.recordings) { RecordingsScreen() } label: { Text("Recordings") }
            SwiftUI.Tab(value: Tab.settings) { PendingScreen(title: "Settings") } label: {
                Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
            }
        }
        .accessibilityIdentifier("tabs")
    }
}

/// A tab whose designed screen is built by a later task of tvos-live.
private struct PendingScreen: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title).font(.system(size: 54, weight: .bold)).foregroundStyle(TVTheme.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
