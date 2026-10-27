import Foundation

/// The rows of the technical information overlay (the Mac's I key, Apple TV's "Technical Info"
/// switch; tvos-stream-info): one definition, so both show the same values. Each platform
/// draws them and the buffer chart in its own size.
public enum StreamInfo {
    public struct Row: Hashable, Sendable {
        public let label: String
        /// "–" when there is nothing to show.
        public let value: String
        /// A divider above the row (between the stream's format and its delivery).
        public let startsSection: Bool
    }

    /// `averageMbps` is the buffer history's average rate: network bytes are shown in seconds
    /// at it, when it is known.
    public static func rows(_ stats: PlaybackStats, averageMbps: Double, now: Date = Date()) -> [Row] {
        var rows: [Row] = []
        func add(_ label: String, _ value: String, section: Bool = false) {
            rows.append(Row(label: label, value: value.isEmpty ? "–" : value, startsSection: section))
        }
        if let method = stats.playMethod { add(String(localized: "Playback", bundle: .module), method) }
        add(String(localized: "Container", bundle: .module), stats.container)
        add(String(localized: "Video", bundle: .module), stats.videoCodec)
        add(String(localized: "Resolution", bundle: .module), stats.resolution)
        add(String(localized: "Frame rate", bundle: .module), stats.frameRate > 0 ? String(format: "%.2f fps", stats.frameRate) : "")
        add(String(localized: "Decoder", bundle: .module), stats.decoder)
        add(String(localized: "Pixel format", bundle: .module), stats.pixelFormat)
        add(String(localized: "Dynamic range", bundle: .module), stats.dynamicRange)
        add(String(localized: "Deinterlacing", bundle: .module), stats.deinterlace)
        add(String(localized: "Audio", bundle: .module), stats.audio)
        add(String(localized: "Bit rate", bundle: .module), String(format: "%.1f Mbit/s", stats.bitrateMbps))
        add(String(localized: "Buffer", bundle: .module), buffer(stats, averageMbps: averageMbps), section: true)
        if let stored = stats.timeshiftStored {
            add(String(localized: "Timeshift buffer", bundle: .module), String(localized: "\(clock(stored)) stored", bundle: .module))
        }
        add(String(localized: "Connection", bundle: .module), stats.connectTime > 0
            ? String(format: String(localized: "%.0f ms to first response", bundle: .module), stats.connectTime * 1000) : "")
        add(String(localized: "Startup", bundle: .module), stats.startupTime > 0
            ? String(format: String(localized: "%.1f s to first frame", bundle: .module), stats.startupTime) : "")
        add(String(localized: "Reconnects", bundle: .module), reconnects(stats, now: now))
        add(String(localized: "Rebuffers", bundle: .module), "\(stats.rebuffers)")
        add(String(localized: "Dropped", bundle: .module), String(localized: "\(stats.droppedFrames) frames", bundle: .module)
            + (stats.duplicatesDropped > 0 ? " · " + String(localized: "\(stats.duplicatesDropped) duplicates", bundle: .module) : ""))
        if stats.decodeFailures > 0 {
            add(String(localized: "Decode errors", bundle: .module), String(localized: "\(stats.decodeFailures) frames", bundle: .module))
        }
        return rows
    }

    private static func buffer(_ stats: PlaybackStats, averageMbps: Double) -> String {
        if let ahead = stats.timeshiftAhead {
            let disk = ahead >= 60 ? clock(ahead) : String(format: "%.1f s", ahead)
            return String(format: "%.1f s", stats.bufferSeconds) + " + " + String(localized: "Disk \(disk)", bundle: .module)
        }
        let network = Double(stats.networkBufferBytes)
        let networkText = network >= 1_000_000 ? String(format: "%.1f MB", network / 1_000_000) : String(format: "%.0f KB", network / 1000)
        let rate = averageMbps * 125_000
        let networkSeconds = rate > 0 ? String(format: " ≈ %.1f s", network / rate) : ""
        return String(format: "%.1f s", stats.bufferSeconds) + " + " + String(localized: "network \(networkText)\(networkSeconds)", bundle: .module)
    }

    private static func reconnects(_ stats: PlaybackStats, now: Date) -> String {
        var parts = [String(localized: "\(stats.seamlessReconnects) seamless", bundle: .module)]
        if stats.restarts > 0 { parts.append(String(localized: "\(stats.restarts) restarts", bundle: .module)) }
        var text = parts.joined(separator: " · ")
        if stats.isReconnecting {
            text += " · " + String(localized: "connecting…", bundle: .module)
        } else if let at = stats.lastReconnectAt {
            let ago = Int(now.timeIntervalSince(at))
            let when = ago < 60 ? String(localized: "\(ago) s ago", bundle: .module) : String(localized: "\(ago / 60) min ago", bundle: .module)
            text += "\n" + String(localized: "last \(when): \(stats.lastReconnectReason ?? "")", bundle: .module)
        }
        return text
    }

    /// "1:02:03" or "2:03".
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
