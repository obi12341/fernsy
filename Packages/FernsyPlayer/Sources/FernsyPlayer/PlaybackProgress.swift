import Combine
import Foundation

/// Position/duration live in their own object so that 10 Hz clock updates only
/// re-render the transport bar, not the whole player.
public final class PlaybackProgress: ObservableObject {
    @Published public var position: Double = 0
    @Published public var duration: Double = 0
    @Published public var buffered: Double = 0
    /// Timeshift: buffer time range that can be played, and the clock time of `position`.
    @Published public var liveStart: Double = 0
    @Published public var liveEnd: Double = 0
    @Published public var wallClock: Date?
    /// Timeshift: playback follows the live stream (not paused or rewound since). Measured
    /// distance to the newest data is no good for this: providers deliver in bursts.
    @Published public var followsLive = true

    /// Seconds behind live (0 while following live).
    public var behindLive: Double { followsLive ? 0 : max(0, liveEnd - position - PlayerEngine.liveLead) }
}
