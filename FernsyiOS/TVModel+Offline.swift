import FernsyCore
import Foundation

/// Leaving the offline state on iPad and iPhone: retry on coming to the front and with growing
/// pauses while offline (offline-recording-downloads).
extension TVModel {
    /// The app comes to the front: offline, try at once (the network may have come back while
    /// it was suspended, which the path monitor then never reports).
    func appBecameActive() {
        if signIn == .offline { Task { await retrySignIn() } }
        // Positions and Jellyfin's rows from the other devices (continue-watching-fresh).
        refreshFromOtherDevices()
        // The paired server's state may have changed meanwhile (headless-recorder design 3).
        if CloudFeature.isEnabled { Task { await cloud.refreshServer() } }
    }

    func retrySignIn() async {
        guard signIn == .offline, let credentials else { return }
        await signIn(credentials, remember: false)
        guard signIn == .signedIn else { return }
        if let downloads { await downloads.resume() }
        if CloudFeature.isEnabled { await cloud.refresh() }
    }

    /// While offline, tries again with growing pauses (2 s up to 60 s): a request that timed out
    /// can leave the app offline while the path monitor already says there is network, and then
    /// no path change comes to end it (seen on the iPad after airplane mode, 2026-10-30).
    func retryWhileOffline() {
        guard offlineRetry == nil else { return }
        offlineRetry = Task { [weak self] in
            var delay = 2.0
            while !Task.isCancelled, let state = self?.signIn, state == .offline || state == .signingIn {
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                if self.signIn == .offline && self.isNetworkAvailable { await self.retrySignIn() }
                delay = min(delay * 2, 60)
            }
            self?.offlineRetry = nil
        }
    }
}
