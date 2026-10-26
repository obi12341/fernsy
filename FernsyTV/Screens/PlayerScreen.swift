import FernsyPlayer
import SwiftUI

/// Placeholder: the picture full screen with a minimal overlay. Remote: Play/Pause pauses,
/// Left goes back 10 s, Right forward 10 s, Down back to live, Back closes.
struct PlayerScreen: View {
    @EnvironmentObject private var model: TVModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVVideoSurface(engine: model.engine).ignoresSafeArea()
            PlayerOverlay(engine: model.engine, progress: model.engine.progress, title: model.playing?.displayName ?? "")
        }
        .focusable()
        .onPlayPauseCommand { model.togglePause() }
        .onMoveCommand { direction in
            switch direction {
            case .left: model.skip(by: -10)
            case .right: model.skip(by: 10)
            case .down: model.goLive()
            default: break
            }
        }
        .onExitCommand { model.stop() }
    }
}

private struct PlayerOverlay: View {
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var progress: PlaybackProgress
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title).font(.title2.bold())
            HStack(spacing: 16) {
                Text(stateText)
                if !isPlayingOrPaused {
                    EmptyView()
                } else if progress.followsLive {
                    Text("LIVE").foregroundStyle(.red).bold()
                } else if let wall = progress.wallClock {
                    Text(wall.formatted(date: .omitted, time: .standard)).monospacedDigit()
                }
            }
            .font(.callout)
        }
        .padding(40)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player.state")
        .accessibilityValue(stateValue)
    }

    private var isPlayingOrPaused: Bool { engine.status == .playing || engine.status == .paused }

    /// Stable values for the UI test, independent of the UI language.
    private var stateValue: String {
        switch engine.status {
        case .playing: "playing"
        case .paused: "paused"
        case .buffering, .loading: "loading"
        case .failed: "failed"
        case .ended: "ended"
        case .idle: "idle"
        }
    }

    private var stateText: LocalizedStringKey {
        switch engine.status {
        case .playing: "Playing"
        case .paused: "Paused"
        case .buffering, .loading: "Loading …"
        case .failed(let message): "\(message)"
        case .ended: "Ended"
        case .idle: ""
        }
    }
}
