import AVFoundation
import FernsyCore
import FernsyPlayer
import SwiftUI

/// Fernsy on iPhone and iPad. The model, image pipeline and player layers are the Apple TV app's
/// (shared from FernsyTV/, ios-app design 2); the screens in this folder are drawn for touch.
@main
struct FernsyiOSApp: App {
    /// One model for the app's lifetime, as on Apple TV: a second one would sign in and stream twice.
    @ObservedObject private var model = TVModel.shared
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    #if DEBUG
    private static let debugServer = TVDebugServer()
    #endif

    init() {
        // Playback keeps its sound in Picture in Picture and on AirPlay (ios-app design 5, 6).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #if DEBUG
        Self.debugServer.startIfRequested(model: TVModel.shared)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appWillLeave() }
        }
    }
}

/// Lets the player lock an iPhone to landscape while it shows (`AppDelegateOrientation`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { AppDelegateOrientation.mask }
    }
}
