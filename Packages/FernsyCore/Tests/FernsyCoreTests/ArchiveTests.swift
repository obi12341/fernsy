import Foundation
import Testing
@testable import FernsyCore

/// The provider's archive (catch-up 1.1): archive days, the server's time zone, the timeshift URL
/// and which past shows can be played.
struct ArchiveTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func channel(archive: Int?, days: Int? = nil) -> LiveChannel {
        var json: [String: Any] = ["stream_id": 101, "name": "Das Erste HD"]
        if let archive { json["tv_archive"] = archive }
        if let days { json["tv_archive_duration"] = "\(days)" }
        return try! JSONDecoder().decode(LiveChannel.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func show(hoursAgo: Double, length: Double = 1.5) -> EPGEntry {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        return EPGEntry(id: "s", title: "Tatort", description: "", start: start, end: start.addingTimeInterval(length * 3600))
    }

    @Test func archiveDaysFromTheCatalog() {
        #expect(channel(archive: 1, days: 5).archiveDays == 5)
        #expect(channel(archive: 1).archiveDays == 1)
        #expect(channel(archive: 0, days: 5).archiveDays == 0)
        #expect(channel(archive: nil).archiveDays == 0)
    }

    @Test func playableWithinTheArchiveOnly() {
        let five = channel(archive: 1, days: 5)
        #expect(Archive.isPlayable(show(hoursAgo: 48), on: five, now: now))
        #expect(Archive.isPlayable(show(hoursAgo: 0.5), on: five, now: now))   // running
        #expect(!Archive.isPlayable(show(hoursAgo: 6 * 24), on: five, now: now))
        #expect(!Archive.isPlayable(show(hoursAgo: -1), on: five, now: now))   // later
        #expect(!Archive.isPlayable(show(hoursAgo: 2), on: channel(archive: 0), now: now))
        #expect(Archive.reach(of: [five, channel(archive: 1, days: 30)]) == Archive.maxDays)
        #expect(Archive.reach(of: [channel(archive: 0)]) == 0)
    }

    @Test func serverTimeZoneByNameOrClock() {
        #expect(AccountInfo.timeZone(name: "Europe/Berlin", timeNow: nil, now: now)?.identifier == "Europe/Berlin")
        // 1_800_000_000 is 2027-01-15 08:00:00 UTC; the server's clock two hours ahead.
        let derived = AccountInfo.timeZone(name: "Not/AZone", timeNow: "2027-01-15 10:00:07", now: now)
        #expect(derived?.secondsFromGMT() == 7200)
        #expect(AccountInfo.timeZone(name: nil, timeNow: nil, now: now) == nil)
    }

    @Test func timeshiftURLInTheServersZone() throws {
        let client = XtreamClient(credentials: XtreamCredentials(server: "http://tv.test:8080", username: "u", password: "p"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)   // 08:00 UTC
        let berlin = try #require(client.archiveURL(channel: 101, start: start, minutes: 95, timeZone: TimeZone(identifier: "Europe/Berlin")))
        #expect(berlin.absoluteString == "http://tv.test:8080/timeshift/u/p/95/2027-01-15:09-00/101.ts")
        let utc = try #require(client.archiveURL(channel: 101, start: start, minutes: 95, timeZone: nil))
        #expect(utc.absoluteString.contains("/2027-01-15:08-00/"))
        #expect(Archive.minutes(for: show(hoursAgo: 3, length: 1.5)) == 95)
    }
}

/// The guide's kept range (catch-up 1.2): three hours back, or the archive's days.
struct EPGKeptRangeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(hoursAgo: Double) -> EPGEntry {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        return EPGEntry(id: "\(hoursAgo)", title: "Show", description: "", start: start, end: start.addingTimeInterval(1800))
    }

    @Test func archiveChannelsKeepTheirDays() async {
        let list = [entry(hoursAgo: 60), entry(hoursAgo: 30), entry(hoursAgo: 2), entry(hoursAgo: -5)]
        let plain = await EPGStore.clean(list, keepDays: 0, now: now)
        #expect(plain.map(\.id) == ["2.0", "-5.0"])
        let threeDays = await EPGStore.clean(list, keepDays: 3, now: now)
        #expect(threeDays.map(\.id) == ["60.0", "30.0", "2.0", "-5.0"])
        let oneDay = await EPGStore.clean(list, keepDays: 1, now: now)
        #expect(oneDay.map(\.id) == ["2.0", "-5.0"])
    }
}
