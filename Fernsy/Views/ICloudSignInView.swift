import FernsyCore
import SwiftUI

/// The window's content while signing in with the logins in iCloud at launch
/// (icloud-auto-signin): icon, title and the steps, a spinner while one runs, a checkmark when done.
struct ICloudSignInView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Signing in with your iCloud login").font(.title.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(app.iCloudSteps) { step in
                    HStack(spacing: 10) {
                        ZStack {
                            if step.done {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(width: 18, height: 18)
                        ICloudSignInStepText(step: step).foregroundStyle(step.done ? .primary : .secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            // Room for all four steps from the start: icon and title stay where they are.
            .frame(width: 360, height: 4 * 18 + 3 * 10, alignment: .topLeading)
            .animation(.easeOut(duration: 0.25), value: app.iCloudSteps)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A step's words: what runs ("Signing in to …") or what is done ("Signed in to …"). One Text
/// whose words change, so a step turning done cross-fades in place instead of two lines overlapping.
struct ICloudSignInStepText: View {
    let step: ICloudSignInStep

    var body: some View {
        words.contentTransition(.opacity)
    }

    private var words: Text {
        switch (step.kind, step.done) {
        case (.found, false): Text("Looking for your login in iCloud …")
        case (.found, true): Text("Login found in iCloud")
        case (.provider, false): Text("Signing in to \(step.server) …")
        case (.provider, true): Text("Signed in to \(step.server)")
        case (.channels, false): Text("Loading channels …")
        case (.channels, true): Text("Channels loaded")
        case (.jellyfin, false): Text("Signing in to Jellyfin \(step.server) …")
        case (.jellyfin, true): Text("Signed in to Jellyfin \(step.server)")
        }
    }
}
