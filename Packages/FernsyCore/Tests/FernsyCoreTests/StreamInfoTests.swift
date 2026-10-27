import Foundation
import Testing
@testable import FernsyCore

/// The technical information rows shared by the Mac and the Apple TV (tvos-stream-info).
struct StreamInfoTests {
    private func values(_ stats: PlaybackStats, averageMbps: Double = 0, now: Date = Date()) -> [String: String] {
        Dictionary(uniqueKeysWithValues: StreamInfo.rows(stats, averageMbps: averageMbps, now: now).map { ($0.label, $0.value) })
    }

    @Test func rowOrderAndSection() {
        let rows = StreamInfo.rows(PlaybackStats(), averageMbps: 0)
        #expect(rows.map(\.label) == ["Container", "Video", "Resolution", "Frame rate", "Decoder", "Pixel format", "Dynamic range",
                                     "Deinterlacing", "Audio", "Bit rate", "Buffer", "Connection", "Startup", "Reconnects",
                                     "Rebuffers", "Dropped"])
        #expect(rows.filter(\.startsSection).map(\.label) == ["Buffer"])
    }

    @Test func emptyValuesShowADash() {
        let v = values(PlaybackStats())
        #expect(v["Container"] == "–")
        #expect(v["Frame rate"] == "–")
        #expect(v["Deinterlacing"] == "–")
        #expect(v["Connection"] == "–")
    }

    @Test func optionalRowsOnlyWhenTheyHaveSomethingToSay() {
        var stats = PlaybackStats()
        #expect(values(stats)["Dropped"] == "0 frames")
        #expect(values(stats)["Decode errors"] == nil)
        #expect(values(stats)["Playback"] == nil)
        stats.duplicatesDropped = 3
        stats.decodeFailures = 2
        stats.playMethod = "Direct play"
        stats.timeshiftStored = 3723
        let v = values(stats)
        #expect(v["Dropped"] == "0 frames · 3 duplicates")
        #expect(v["Decode errors"] == "2 frames")
        #expect(v["Playback"] == "Direct play")
        #expect(v["Timeshift buffer"] == "1:02:03 stored")
        #expect(StreamInfo.rows(stats, averageMbps: 0).first?.label == "Playback")
    }

    @Test func bufferInSecondsAtTheAverageRate() {
        var stats = PlaybackStats(bufferSeconds: 8, networkBufferBytes: 2_500_000)
        // 4 Mbit/s = 500 KB/s: 2.5 MB are 5 s.
        #expect(values(stats, averageMbps: 4)["Buffer"] == "8.0 s + network 2.5 MB ≈ 5.0 s")
        #expect(values(stats)["Buffer"] == "8.0 s + network 2.5 MB")
        stats.timeshiftAhead = 3.4
        #expect(values(stats)["Buffer"] == "8.0 s + Disk 3.4 s")
    }

    @Test func reconnectsWithTheLastOne() {
        let now = Date()
        var stats = PlaybackStats(seamlessReconnects: 2, lastReconnectReason: "stall", lastReconnectAt: now.addingTimeInterval(-30))
        #expect(values(stats, now: now)["Reconnects"] == "2 seamless\nlast 30 s ago: stall")
        stats.restarts = 2
        stats.isReconnecting = true
        #expect(values(stats, now: now)["Reconnects"] == "2 seamless · 2 restarts · connecting…")
    }
}
