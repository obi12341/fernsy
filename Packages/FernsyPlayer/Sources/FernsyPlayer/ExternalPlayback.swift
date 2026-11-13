import FernsyCore
import Foundation

/// Hooks for a controller that plays something other than a plain URL (Jellyfin): a transcode
/// started mid-item, seeking by restarting, falling back when the source cannot be opened.
public struct ExternalPlayback {
    /// Item position at which the current stream starts (transcodes started with an offset).
    public var timelineOffset: Double = 0
    /// The whole item's length when the stream does not know it (progressive transcodes).
    public var duration: Double?
    /// Non-seekable stream: the controller restarts at the requested item position.
    public var restartAt: ((Double) -> Void)?
    /// The stream failed before playing; return true when the controller takes over.
    public var onFailedBeforeStart: ((String) -> Bool)?
    /// The stream failed while playing (e.g. the server rejected the token); return true when
    /// the controller recovers by loading again.
    public var onFailedAfterStart: ((String) -> Bool)?
    /// Track choices the controller handles itself (external files, transcode restarts);
    /// return false to let the engine switch the stream's own track.
    public var selectAudio: ((MediaTrack) -> Bool)?
    public var selectSubtitle: ((MediaTrack?) -> Bool)?
    /// Tracks the controller already chose (stream ids); nil = the engine's language rules.
    public var tracks: TrackRequest?
    /// A stream opened (each restart opens its own); the controller adjusts the track menus.
    public var onOpened: (() -> Void)?
    /// "Direct play" / "Transcode", shown in the info overlay.
    public var methodLabel: String?
    /// The stream comes from the IPTV provider (an archived show), so "IPTV only with VPN"
    /// applies to it; false for Jellyfin (vpn-guard).
    public var contactsProvider = true

    public init(timelineOffset: Double = 0, duration: Double? = nil, restartAt: ((Double) -> Void)? = nil, onFailedBeforeStart: ((String) -> Bool)? = nil, onFailedAfterStart: ((String) -> Bool)? = nil, selectAudio: ((MediaTrack) -> Bool)? = nil, selectSubtitle: ((MediaTrack?) -> Bool)? = nil, tracks: TrackRequest? = nil, onOpened: (() -> Void)? = nil, methodLabel: String? = nil) {
        self.timelineOffset = timelineOffset
        self.duration = duration
        self.restartAt = restartAt
        self.onFailedBeforeStart = onFailedBeforeStart
        self.onFailedAfterStart = onFailedAfterStart
        self.selectAudio = selectAudio
        self.selectSubtitle = selectSubtitle
        self.tracks = tracks
        self.onOpened = onOpened
        self.methodLabel = methodLabel
    }
}
