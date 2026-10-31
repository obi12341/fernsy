#if os(tvOS)
import AVKit
import Combine
import FernsyCore
import FernsyPlayer
import UIKit

/// Asks tvOS for the frame rate and dynamic range of what the full-screen player shows
/// (tvos-match-content), so a TV with "Match Content" switches to them. The preview pane never
/// asks; closing the player hands the mode back after a grace period; the first start of an
/// item waits while the TV switches.
@MainActor
final class DisplayModeController {
    /// "Match Frame Rate and Dynamic Range" per account, per Apple TV (design 5): the IPTV
    /// account's (live TV, catch-up, films, series, recordings; off by default, zapping would
    /// switch) and the Jellyfin server's (on by default).
    static let iptvKey = "player.matchDisplayMode.iptv"
    static let jellyfinKey = "player.matchDisplayMode.jellyfin"
    /// Closing the player releases the mode only after this, so episode to episode keeps it (design 3).
    static let releaseDelay: Duration = .seconds(2)
    /// How long tvOS gets to begin a switch, and how long the start waits for it in all (design 4).
    static let switchBeginWait: Duration = .milliseconds(300)
    static let holdLimit: Duration = .seconds(5)

    private weak var model: TVModel?
    private var current: DisplayModeRequest?
    private var releaseTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var changes: Set<AnyCancellable> = []

    init(model: TVModel) {
        self.model = model
        UserDefaults.standard.register(defaults: [Self.iptvKey: false, Self.jellyfinKey: true])
        let engine = model.engine
        engine.startHold.isEnabled = isAnyEnabled
        // `@Published` sends before it stores: look again on the next turn of the run loop.
        let poke: () -> Void = { [weak self] in DispatchQueue.main.async { self?.update() } }
        engine.$displayFormat.sink { _ in poke() }.store(in: &changes)
        engine.$media.sink { _ in poke() }.store(in: &changes)
        model.$playing.sink { _ in poke() }.store(in: &changes)
        model.$playingVOD.sink { _ in poke() }.store(in: &changes)
        model.$playingRecording.sink { _ in poke() }.store(in: &changes)
        model.$previewing.sink { _ in poke() }.store(in: &changes)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { _ in poke() }.store(in: &changes)
    }

    /// The hold is armed on load, before the item's account is known here: armed when either
    /// switch is on, and released at once for an item whose account has it off.
    private var isAnyEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.iptvKey) || UserDefaults.standard.bool(forKey: Self.jellyfinKey)
    }

    /// The switch of the playing item's account.
    private var isEnabledForPlaying: Bool {
        if case .jellyfin? = model?.playingVOD { return UserDefaults.standard.bool(forKey: Self.jellyfinKey) }
        return UserDefaults.standard.bool(forKey: Self.iptvKey)
    }

    /// A full-screen player is up (live, film, episode, Jellyfin, catch-up, cloud or recording).
    private var isFullScreen: Bool {
        guard let model else { return false }
        return model.playing != nil || model.playingVOD != nil || model.playingRecording != nil
    }

    /// AVKit adds `avDisplayManager` to `UIWindow`. Using it only through that property links
    /// nothing, so the linker drops AVKit and the property is missing at run time: this class
    /// reference keeps AVKit linked.
    static let managerClass: AnyClass = AVDisplayManager.self

    /// The key window's display manager; the tvOS simulator's windows have none.
    private var manager: AVDisplayManager? {
        _ = Self.managerClass
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow),
              window.responds(to: NSSelectorFromString("avDisplayManager")) else { return nil }
        return window.avDisplayManager
    }

    private func update() {
        guard let model else { return }
        let engine = model.engine
        let anyEnabled = isAnyEnabled
        if engine.startHold.isEnabled != anyEnabled { engine.startHold.isEnabled = anyEnabled }
        guard anyEnabled else {
            // Turned off, even while the player runs: hand the mode back now.
            releaseTask?.cancel()
            releaseTask = nil
            release()
            return
        }
        guard isFullScreen else {
            engine.startHold.release()
            if current != nil && releaseTask == nil {
                releaseTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.releaseDelay)
                    guard !Task.isCancelled, let self, !self.isFullScreen else { return }
                    self.releaseTask = nil
                    self.release()
                }
            }
            return
        }
        releaseTask?.cancel()
        releaseTask = nil
        guard isEnabledForPlaying else {
            // This account's items keep the interface's mode (and a mode asked for another one goes back).
            release()
            return
        }
        if engine.media?.hasVideo == false {
            engine.startHold.release()
            return
        }
        // No picture yet: the hold stays until the first frame tells what it is.
        guard let format = engine.displayFormat else { return }
        let request = format.request
        guard request != current else {
            if engine.startHold.isHeld { AppLog.detail(.player, "display mode: unchanged (\(request))") }
            engine.startHold.release()
            return
        }
        current = request
        guard let manager else {
            // The simulator: what would be asked, for the tests.
            AppLog.info(.player, "display mode: \(request) (no display manager)")
            engine.startHold.release()
            return
        }
        manager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: Float(request.refreshRate), formatDescription: format.formatDescription)
        AppLog.info(.player, "display mode: \(request)" + (manager.isDisplayCriteriaMatchingEnabled ? "" : " (Match Content is off in tvOS)"))
        // Only an item that has not started waits; a running picture keeps playing (design 4).
        guard engine.startHold.isHeld, manager.isDisplayCriteriaMatchingEnabled else {
            engine.startHold.release()
            return
        }
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            while !manager.isDisplayModeSwitchInProgress, clock.now - start < Self.switchBeginWait {
                try? await Task.sleep(for: .milliseconds(30))
            }
            let began = manager.isDisplayModeSwitchInProgress
            while manager.isDisplayModeSwitchInProgress, clock.now - start < Self.holdLimit {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            if began { AppLog.detail(.player, "display mode: switched in \(clock.now - start)") }
            self?.model?.engine.startHold.release()
        }
    }

    private func release() {
        holdTask?.cancel()
        holdTask = nil
        model?.engine.startHold.release()
        guard current != nil else { return }
        current = nil
        manager?.preferredDisplayCriteria = nil
        AppLog.info(.player, "display mode: released")
    }
}
#endif
