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
            if phase == .active { model.appBecameActive() }
        }
    }
}

/// Lets the player lock an iPhone to landscape while it shows (`AppDelegateOrientation`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { AppDelegateOrientation.mask }
    }

    /// A cloud download finished while the app was not running (offline-recording-downloads
    /// design B): the session's events go to the download store, which then calls back.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            AppLog.info(.app, "Fernsy Cloud: background download events for \(identifier)")
            _ = TVModel.shared.downloads
            BackgroundDownloadTransfer.shared.handleEvents(identifier: identifier, completion: completionHandler)
        }
    }
}
