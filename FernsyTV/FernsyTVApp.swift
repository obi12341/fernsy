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
        HangWatch.startIfRequested()
        Self.debugServer.startIfRequested(model: TVModel.shared)
        // IPTV_OPEN=<fernsy:// link>: open or play an item at launch, as a Top Shelf tile does,
        // so UI tests start on the screen they test (faster-ui-tests).
        if let link = ProcessInfo.processInfo.environment["IPTV_OPEN"].flatMap(URL.init(string:)) {
            TVModel.shared.handle(url: link)
        }
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
            // The paired server's state may have changed meanwhile (headless-recorder design 3).
            if phase == .active, CloudFeature.isEnabled { Task { await model.cloud.refreshServer() } }
        }
    }
}
