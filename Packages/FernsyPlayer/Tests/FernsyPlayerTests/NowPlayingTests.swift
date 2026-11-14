import Combine
import Foundation
import MediaPlayer
import Testing
@testable import FernsyPlayer

/// Now Playing and the system's commands (now-playing-controls): commands reach the player's
/// controls, live items offer only play/pause, and clearing hands everything back.
/// Serialized: the command center and the info center are shared by the process.
@Suite(.serialized) struct NowPlayingTests {
    final class Player: NowPlayingPlayer {
        var isPaused = false
        var isLive = false
        var status: PlayerEngine.Status = .playing
        var nowPlayingPosition: Double = 100
        var nowPlayingDuration: Double = 5400
        let subject = PassthroughSubject<Void, Never>()
        var nowPlayingChanges: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
        var calls: [String] = []

        func setPaused(_ paused: Bool) {
            calls.append(paused ? "pause" : "play")
            isPaused = paused
        }
        func togglePause() { calls.append("toggle"); isPaused.toggle() }
        func seek(to position: Double) { calls.append("seek to \(Int(position))") }
        func seek(by delta: Double) { calls.append("seek by \(Int(delta))") }
    }

    private func setUp(live: Bool = false) -> (NowPlaying, Player) {
        let player = Player()
        player.isLive = live
        let nowPlaying = NowPlaying()
        nowPlaying.attach(player)
        nowPlaying.show(title: "Film", subtitle: "Series · S1E2")
        return (nowPlaying, player)
    }

    @Test func commandsReachThePlayer() {
        let (nowPlaying, player) = setUp()
        #expect(nowPlaying.handle(.pause) == .success)
        #expect(nowPlaying.handle(.play) == .success)
        #expect(nowPlaying.handle(.toggle) == .success)
        #expect(nowPlaying.handle(.skipForward) == .success)
        #expect(nowPlaying.handle(.skipBackward) == .success)
        #expect(nowPlaying.handle(.position(1234)) == .success)
        #expect(player.calls == ["pause", "play", "toggle", "seek by 15", "seek by -15", "seek to 1234"])
        nowPlaying.clear()
    }

    @Test func playAndPauseAreIdempotent() {
        let (nowPlaying, player) = setUp()
        nowPlaying.handle(.pause)
        nowPlaying.handle(.pause)
        #expect(player.isPaused)
        nowPlaying.handle(.play)
        nowPlaying.handle(.play)
        #expect(!player.isPaused)
        nowPlaying.clear()
    }

    @Test func liveOffersOnlyPlayAndPause() {
        let (nowPlaying, player) = setUp(live: true)
        #expect(nowPlaying.handle(.pause) == .success)
        #expect(nowPlaying.handle(.skipForward) == .commandFailed)
        #expect(nowPlaying.handle(.position(10)) == .commandFailed)
        #expect(player.calls == ["pause"])
        let center = MPRemoteCommandCenter.shared()
        #expect(center.togglePlayPauseCommand.isEnabled)
        #expect(!center.skipForwardCommand.isEnabled)
        #expect(!center.changePlaybackPositionCommand.isEnabled)
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        #expect(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(info[MPMediaItemPropertyPlaybackDuration] == nil)
        #expect(info[MPMediaItemPropertyTitle] as? String == "Film")
        nowPlaying.clear()
    }

    @Test func onDemandShowsPositionAndRate() {
        let (nowPlaying, player) = setUp()
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        #expect(info[MPMediaItemPropertyPlaybackDuration] as? Double == 5400)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 100)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(info[MPMediaItemPropertyArtist] as? String == "Series · S1E2")
        #expect(MPRemoteCommandCenter.shared().skipForwardCommand.isEnabled)

        player.isPaused = true
        nowPlaying.update()
        info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)

        player.isPaused = false
        player.status = .buffering
        nowPlaying.update()
        info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)

        // A seek while paused shows the new position.
        player.isPaused = true
        player.status = .paused
        nowPlaying.update()
        player.nowPlayingPosition = 2000
        nowPlaying.update()
        info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 2000)
        nowPlaying.clear()
    }

    @Test func clearHandsEverythingBack() {
        let (nowPlaying, player) = setUp()
        nowPlaying.clear()
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand] {
            #expect(!command.isEnabled)
        }
        #expect(nowPlaying.handle(.pause) == .noActionableNowPlayingItem)
        #expect(player.calls.isEmpty)
    }
}
