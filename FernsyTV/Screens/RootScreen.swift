import SwiftUI

/// Placeholder screens (tvos-foundation): plain SwiftUI that the designed screens replace.
/// Each reads only TVModel and keeps the accessibility identifiers the UI test uses.
struct RootScreen: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        Group {
            switch model.signIn {
            case .signedIn:
                ChannelListScreen()
            case .signingIn where model.channels.isEmpty:
                ProgressView("Signing in …")
            default:
                SignInScreen()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { model.playing != nil }, set: { if !$0 { model.stop() } })) {
            PlayerScreen()
        }
    }
}
