import Combine
import FernsyCore
import Foundation
import MediaPlayer

/// What Now Playing reads from the player and the controls a system command calls
/// (now-playing-controls design 2). The engine conforms; the tests use a stand-in.
public protocol NowPlayingPlayer: AnyObject {
    var isPaused: Bool { get }
    var isLive: Bool { get }
    var status: PlayerEngine.Status { get }
    var nowPlayingPosition: Double { get }
    var nowPlayingDuration: Double { get }
    /// Fires when any of the above may have changed.
    var nowPlayingChanges: AnyPublisher<Void, Never> { get }
    func setPaused(_ paused: Bool)
    func togglePause()
    func seek(to position: Double)
    func seek(by delta: Double)
}

extension PlayerEngine: NowPlayingPlayer {
    public var nowPlayingPosition: Double { progress.position }
    public var nowPlayingDuration: Double { progress.duration }
    public var nowPlayingChanges: AnyPublisher<Void, Never> {
        Publishers.Merge4($isPaused.map { _ in }, $status.map { _ in },
                          progress.$duration.map { _ in }, progress.$position.map { _ in })
            .eraseToAnyPublisher()
    }
}

/// The playing item as Now Playing, and the system's play, pause, skip and position commands
/// (AirPods, Lock Screen, Control Center, media keys) on Mac, iPhone, iPad and Apple TV
/// (playback "System media controls"). The app hands over the item's text; the player's state
/// comes from the attached player. One per app, like the player.
public final class NowPlaying {
    public static let shared = NowPlaying()

    public enum Command: Equatable {
        case play, pause, toggle, skipForward, skipBackward
        case position(Double)
    }

    /// The system's usual skip interval.
    static let skipInterval: Double = 15

    private weak var player: NowPlayingPlayer?
    private var changes: AnyCancellable?
    private var item: (title: String, subtitle: String?)?
    /// The last written elapsed time and rate, to notice seeks without writing every tick.
    private var written: (elapsed: Double, rate: Double, at: Date)?
    private var lastKey: String?
    /// A new item is logged once it has started (before that the player may still be on the old one).
    private var logPending = false
    private var registered = false

    init() {}

    /// The player whose state is shown and whose controls the commands use.
    public func attach(_ player: NowPlayingPlayer) {
        guard self.player !== player else { return }
        self.player = player
        // @Published fires before the value changes: read it on the next turn of the main queue.
        changes = player.nowPlayingChanges.receive(on: DispatchQueue.main).sink { [weak self] in self?.update() }
    }

    /// The item now shown in the player, with the player's title and second line.
    public func show(title: String, subtitle: String?) {
        registerCommands()
        if item?.title != title { logPending = true }
        if item?.title != title || item?.subtitle != subtitle { lastKey = nil }
        item = (title, subtitle)
        update()
    }

    /// The player closed: Now Playing and the commands go back to other apps.
    public func clear() {
        guard item != nil else { return }
        item = nil
        logPending = false
        written = nil
        lastKey = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
        setCommandsEnabled(live: true, enabled: false)
        AppLog.info(.player, "now playing cleared")
    }

    /// Carries out a system command on the player (also the tests' entry point).
    @discardableResult
    func handle(_ command: Command) -> MPRemoteCommandHandlerStatus {
        guard item != nil, let player else { return .noActionableNowPlayingItem }
        AppLog.info(.player, "now playing command: \(command)")
        switch command {
        case .play: player.setPaused(false)
        case .pause: player.setPaused(true)
        case .toggle: player.togglePause()
        case .skipForward, .skipBackward, .position:
            guard !player.isLive else { return .commandFailed }
            switch command {
            case .skipForward: player.seek(by: Self.skipInterval)
            case .skipBackward: player.seek(by: -Self.skipInterval)
            case .position(let time): player.seek(to: time)
            default: break
            }
        }
        return .success
    }

    /// Writes the info when the item, the state or the position (a seek) changed.
    func update() {
        guard let item, let player else { return }
        if logPending, player.status == .playing || player.status == .paused {
            logPending = false
            AppLog.info(.player, "now playing: \(item.title), \(player.isLive ? "live" : "on demand")")
        }
        let rate: Double = player.status == .playing && !player.isPaused ? 1 : 0
        let elapsed = player.nowPlayingPosition
        let key = "\(player.isLive) \(rate) \(Int(player.nowPlayingDuration))"
        var jumped = false
        if let written, !player.isLive {
            let expected = written.elapsed + Date().timeIntervalSince(written.at) * written.rate
            jumped = abs(expected - elapsed) > 2
        }
        guard key != lastKey || jumped else { return }
        lastKey = key
        written = (elapsed, rate, Date())
        MPNowPlayingInfoCenter.default().nowPlayingInfo = Self.info(
            title: item.title, subtitle: item.subtitle, live: player.isLive,
            rate: rate, elapsed: elapsed, duration: player.nowPlayingDuration)
        #if os(macOS)
        // macOS picks the Now Playing app by this; iOS and tvOS by the active audio session.
        MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
        #endif
        setCommandsEnabled(live: player.isLive, enabled: true)
    }

    static func info(title: String, subtitle: String?, live: Bool, rate: Double, elapsed: Double, duration: Double) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: live,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
        ]
        if let subtitle { info[MPMediaItemPropertyArtist] = subtitle }
        if !live {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)
            if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        }
        return info
    }

    private func registerCommands() {
        guard !registered else { return }
        registered = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.handle(.play) ?? .commandFailed }
        center.pauseCommand.addTarget { [weak self] _ in self?.handle(.pause) ?? .commandFailed }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.handle(.toggle) ?? .commandFailed }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipForwardCommand.addTarget { [weak self] _ in self?.handle(.skipForward) ?? .commandFailed }
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.handle(.skipBackward) ?? .commandFailed }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.handle(.position(event.positionTime)) ?? .commandFailed
        }
    }

    /// Play and pause for every item; skip and position only on demand.
    private func setCommandsEnabled(live: Bool, enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand] {
            command.isEnabled = enabled
        }
        for command in [center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand] {
            command.isEnabled = enabled && !live
        }
    }
}
