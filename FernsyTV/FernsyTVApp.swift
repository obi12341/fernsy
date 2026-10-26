import FernsyCore
import FernsyPlayer
import SwiftUI

/// Fernsy on Apple TV. The screens in Screens/ are placeholders that the designed screens
/// replace (DEVELOPMENT.md › Apple TV); they read only TVModel.
@main
struct FernsyTVApp: App {
    /// One model for the app's lifetime: SwiftUI may create the App value more than once, and
    /// a second model would sign in and stream a second time.
    @ObservedObject private var model = TVModel.shared

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
            RootScreen().environmentObject(model)
        }
    }
}
