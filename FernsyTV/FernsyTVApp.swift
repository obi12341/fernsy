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
    @Environment(\.scenePhase) private var scenePhase

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
                // The Top Shelf's tiles (tvos-top-shelf design 3); applied once the item has loaded.
                .onOpenURL { model.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.appWillLeave()
                // The Home Screen shows the Top Shelf next: what was just watched belongs in it.
                model.writeTopShelfNow()
            }
        }
    }
}
