import FernsyCore
import SwiftUI

/// The launch screen while signing in with the logins in iCloud (icloud-auto-signin): icon,
/// title and the steps, each with a ring while it runs and a checkmark when done.
struct ICloudSignInScreen: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        VStack(spacing: 44) {
            Image("FernsyIcon").resizable().frame(width: 220, height: 220)
            Text("Signing in with your iCloud login").font(.system(size: 44, weight: .semibold))
            VStack(alignment: .leading, spacing: 22) {
                ForEach(model.iCloudSteps) { step in
                    HStack(spacing: 22) {
                        ZStack {
                            if step.done {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(TVTheme.accentLight)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                ProgressView()
                            }
                        }
                        .font(.system(size: 34))
                        .frame(width: 44, height: 44)
                        ICloudSignInStepText(step: step).font(.system(size: 30))
                            .foregroundStyle(step.done ? TVTheme.text : TVTheme.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("icloud.step.\(step.kind.rawValue)")
                    .accessibilityValue(step.done ? "done" : "running")
                }
            }
            // Room for all four steps from the start: icon and title stay where they are.
            .frame(width: 900, height: 4 * 44 + 3 * 22, alignment: .topLeading)
            .animation(.easeOut(duration: 0.3), value: model.iCloudSteps)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(TVTheme.text)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("icloud.signingIn")
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
