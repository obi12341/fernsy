import FernsyCore
import SwiftUI

/// The app's frame: the iCloud launch screen, the welcome screen and sign-in without an
/// account, the tabs with one, and the full-screen player over everything (ios-app).
struct RootView: View {
    @EnvironmentObject private var model: TVModel
    @ObservedObject private var presentation = PlayerPresentation.shared

    var body: some View {
        Group {
            // The iCloud launch screen first: it stays until the channels are loaded (icloud-auto-signin).
            if model.signingInFromICloud {
                ICloudSignInView().transition(.opacity)
            } else if model.signIn == .signedIn || !model.channels.isEmpty || model.jellyfin.session != nil {
                MainTabView().transition(.opacity)
            } else if model.signIn == .signingIn && model.startedWithAccount {
                ProgressView("Signing in …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WelcomeView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: model.signingInFromICloud)
        .background(TVTheme.background.ignoresSafeArea())
        .foregroundStyle(TVTheme.text)
        .tint(TVTheme.accentLight)
        .fullScreenCover(isPresented: presentation.binding(model: model), onDismiss: {
            // Back to portrait once the player is gone: asked while it still dismisses (its
            // onDisappear), the turn is refused and the iPhone stays in landscape.
            if !presentation.inPictureInPicture { Orientation.landscapeOnPhone(false) }
        }) {
            PlayerView()
        }
        .alert(model.question?.title ?? "", isPresented: Binding(get: { model.question != nil }, set: { if !$0 { model.question?.answer(false) } }),
               presenting: model.question) { question in
            Button(question.confirm) { question.answer(true) }
            Button(question.cancel, role: .cancel) { question.answer(false) }
        } message: { question in
            Text(verbatim: question.message)
        }
    }
}

/// The tabs (ios-app "Navigation"): a tab bar on iPhone, a sidebar-capable tab bar on iPad.
/// Tabs whose source is not signed in or switched off are left out; Recordings shows Fernsy
/// Cloud's recordings for subscribers.
struct MainTabView: View {
    enum Tab: Hashable { case start, live, films, series, jellyfin, recordings, search, settings }

    @EnvironmentObject private var model: TVModel
    @SceneStorage("tab") private var selection: Tab = .start
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let iptv = model.credentials != nil || !model.channels.isEmpty
        let jellyfin = model.jellyfin.session != nil
        TabView(selection: $selection) {
            SwiftUI.Tab("Start", systemImage: "house", value: Tab.start) {
                StartView()
            }
            if iptv {
                SwiftUI.Tab("Live TV", systemImage: "dot.radiowaves.left.and.right", value: Tab.live) {
                    NavigationStack { LiveTVView() }
                }
                if model.showsIPTVMovies {
                    SwiftUI.Tab("Movies", systemImage: "film", value: Tab.films) {
                        NavigationStack { LibraryGridView(kind: .movies) }
                    }
                }
                if model.showsIPTVSeries {
                    SwiftUI.Tab("Series", systemImage: "tv", value: Tab.series) {
                        NavigationStack { LibraryGridView(kind: .series) }
                    }
                }
            }
            if jellyfin {
                SwiftUI.Tab("Jellyfin", systemImage: "play.rectangle.on.rectangle", value: Tab.jellyfin) {
                    NavigationStack { JellyfinView() }
                }
            }
            // Fernsy Cloud's recordings, for subscribers (add-recording-cloud).
            if CloudFeature.isEnabled && model.cloud.canUseCloud {
                SwiftUI.Tab("Recordings", systemImage: "record.circle", value: Tab.recordings) {
                    NavigationStack { CloudRecordingsView() }
                }
            }
            // An iPhone shows five tabs at most: there Settings opens from Start's gear.
            if sizeClass != .compact {
                SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
                    NavigationStack { SettingsView() }
                }
            }
            SwiftUI.Tab(value: Tab.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .accessibilityIdentifier("tabs")
        #if DEBUG
        // IPTV_TAB=start|live|films|series|jellyfin|search|settings: opens that tab (screenshots
        // without touch input); IPTV_LIVEVIEW=list|guide picks Live TV's view.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if let tab = env["IPTV_TAB"].flatMap(Tab.init(rawValue:)) { selection = tab }
            if let view = env["IPTV_LIVEVIEW"].flatMap(TVModel.LiveView.init(rawValue:)) { model.liveView = view }
        }
        #endif
    }
}

extension MainTabView.Tab: RawRepresentable {
    init?(rawValue: String) {
        switch rawValue {
        case "start": self = .start
        case "live": self = .live
        case "films": self = .films
        case "series": self = .series
        case "jellyfin": self = .jellyfin
        case "recordings": self = .recordings
        case "search": self = .search
        case "settings": self = .settings
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .start: "start"
        case .live: "live"
        case .films: "films"
        case .series: "series"
        case .jellyfin: "jellyfin"
        case .recordings: "recordings"
        case .search: "search"
        case .settings: "settings"
        }
    }
}

/// Whether the full-screen player shows. Picture in Picture hides it while playback goes on, so
/// "playing" alone does not decide it (ios-app design 5).
@MainActor
final class PlayerPresentation: ObservableObject {
    static let shared = PlayerPresentation()
    /// Picture in Picture runs: the player is closed but playback continues.
    @Published var inPictureInPicture = false

    func binding(model: TVModel) -> Binding<Bool> {
        Binding(get: { (model.playing != nil || model.playingVOD != nil) && !self.inPictureInPicture },
                set: { shown in if !shown && !self.inPictureInPicture { model.stop() } })
    }
}
