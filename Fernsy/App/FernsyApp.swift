import SwiftUI

@main
struct FernsyApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup("Fernsy", id: "library") {
            Group {
                if app.credentials == nil {
                    LoginView()
                } else {
                    LibraryView()
                }
            }
            .environmentObject(app)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Katalog aktualisieren") {
                    Task { await app.loadCatalog(forceRefresh: true) }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(app.credentials == nil || app.isLoading)
            }
        }

        // A single player window: Xtream accounts usually allow one stream at a time.
        Window("Wiedergabe", id: "player") {
            PlayerScreen()
                .environmentObject(app)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environmentObject(app)
        }
    }
}
