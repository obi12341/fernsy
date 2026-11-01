import Foundation
import Testing
@testable import FernsyCore

/// The tools' argument and result formats, shared by the Mac's MCP server and the Apple TV and
/// iOS tool runners (cloud-assistant 1.3): argument errors reach the model as clear messages.
struct AssistantToolValuesTests {
    static func message(_ body: () throws -> Any) -> String? {
        do { _ = try body(); return nil } catch { return error.localizedDescription }
    }

    static func jellyfin(_ json: String) throws -> JFItem { try JSONDecoder().decode(JFItem.self, from: Data(json.utf8)) }

    @Test func datesInAndOut() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(try AssistantTools.date(AssistantTools.iso(date)) == date)
        #expect(try AssistantTools.date("2027-01-15T20:15:00Z") == Date(timeIntervalSince1970: 1_800_044_100))
        #expect(try AssistantTools.date("2027-01-15T20:15:00.500Z") == Date(timeIntervalSince1970: 1_800_044_100.5))
        // Without an offset: the device's time zone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let local = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 20, minute: 15)))
        #expect(try AssistantTools.date("2027-01-15T20:15") == local)
        #expect(try AssistantTools.date("2027-01-15 20:15") == local)
        #expect(Self.message { try AssistantTools.date("tonight") } == "Not an ISO 8601 date: tonight")
    }

    @Test func rangeDefaultsToADayAndChecksTheOrder() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let range = try AssistantTools.range([:], now: now)
        #expect(range.from == now && range.to == now.addingTimeInterval(24 * 3600))
        let from = AssistantTools.iso(now), earlier = AssistantTools.iso(now.addingTimeInterval(-60))
        #expect(Self.message { try AssistantTools.range(["from": from, "to": earlier]) } == "'to' must be after 'from'")
    }

    @Test func positions() throws {
        #expect(AssistantTools.clock(3725.9) == "1:02:05")
        #expect(AssistantTools.clock(-3) == "0:00:00")
        #expect(try AssistantTools.position("1:02:05") == 3725)
        #expect(try AssistantTools.position("12:30") == 750)
        #expect(try AssistantTools.position("90.5") == 90.5)
        #expect(AssistantTools.seconds("112 min") == 6720)
        #expect(AssistantTools.seconds("abc") == nil)
        #expect(Self.message { try AssistantTools.position("soon") } == "Positions are seconds or h:mm:ss: soon")
        #expect(AssistantTools.text(NSNumber(value: 42)) == "42")
        #expect(AssistantTools.text("0:10") == "0:10")
    }

    @Test func timingAndRuntime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timing = AssistantTools.timing(position: 600, duration: 3600, running: true, now: now)
        #expect(timing["remaining_seconds"] as? Int == 3000)
        #expect(timing["remaining"] as? String == "0:50:00")
        #expect(timing["ends_at"] as? String == AssistantTools.iso(now.addingTimeInterval(3000)))
        #expect(AssistantTools.timing(position: 0, duration: 60, running: false)["ends_at"] == nil)
        #expect(AssistantTools.runtime(duration: nil, position: 10).isEmpty)
        let started = AssistantTools.runtime(duration: 7200, position: 1800)
        #expect(started["runtime"] as? String == "2:00:00" && started["remaining_seconds"] as? Int == 5400)
        #expect(AssistantTools.runtime(duration: 7200, position: 0)["remaining"] == nil)
    }

    @Test func showsByIdOrChannelAndStart() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let id = AssistantTools.showID(channel: 12, start: start)
        #expect(id == "12:1800000000")
        let byId = try AssistantTools.show(["show_id": id])
        #expect(byId.channelId == 12 && byId.start == start)
        let byStart = try AssistantTools.show(["channel_id": 12, "start": AssistantTools.iso(start)])
        #expect(byStart.channelId == 12 && byStart.start == start)
        #expect(Self.message { try AssistantTools.show(["show_id": "ZDF tonight"]) } == "show_id must look like <channel>:<start epoch>")
        #expect(Self.message { try AssistantTools.show(["channel_id": 12]) } == "Pass show_id, or channel_id and start")
    }

    @Test func seekTakesExactlyOneTarget() throws {
        #expect(try AssistantTools.seekTarget(["by_seconds": -30]) == "by_seconds")
        #expect(try AssistantTools.seekTarget(["to_live": true, "to_show_start": false]) == "to_live")
        let error = "Pass exactly one of by_seconds, to_position, to_time, to_show_start, to_live."
        #expect(Self.message { try AssistantTools.seekTarget([:]) } == error)
        #expect(Self.message { try AssistantTools.seekTarget(["by_seconds": 10, "to_live": true]) } == error)
    }

    @Test func jellyfinEpisodeJSON() throws {
        let item = try Self.jellyfin(#"{"id":"e2","name":"Two","type":"Episode","seriesName":"Show","parentIndexNumber":1,"indexNumber":2,"runTimeTicks":18000000000,"userData":{"playbackPositionTicks":6000000000,"playedPercentage":33.3}}"#)
        let value = AssistantTools.jellyfinJSON(item)
        #expect(value["item_id"] as? String == "jellyfin:e2")
        #expect(value["title"] as? String == "Show S1E2 · Two")
        #expect(value["progress_percent"] as? Int == 33)
        #expect(value["remaining"] as? String == "0:20:00")
    }

    @Test func neighboursKeepSpecialsApart() throws {
        let episodes = AssistantTools.ordered(try [
            Self.jellyfin(#"{"id":"b","name":"B","type":"Episode","parentIndexNumber":1,"indexNumber":2}"#),
            Self.jellyfin(#"{"id":"s","name":"S","type":"Episode","parentIndexNumber":0,"indexNumber":1}"#),
            Self.jellyfin(#"{"id":"a","name":"A","type":"Episode","parentIndexNumber":1,"indexNumber":1}"#),
            Self.jellyfin(#"{"id":"c","name":"C","type":"Episode","parentIndexNumber":2,"indexNumber":1}"#),
        ])
        #expect(episodes.map(\.id) == ["s", "a", "b", "c"])
        let around = AssistantTools.neighbours(of: episodes[2], in: episodes)
        #expect(around.previous?.id == "a" && around.next?.id == "c")
        let first = AssistantTools.neighbours(of: episodes[1], in: episodes)
        #expect(first.previous == nil && first.next?.id == "b")
        let special = AssistantTools.neighbours(of: episodes[0], in: episodes)
        #expect(special.previous == nil && special.next == nil)
        #expect(AssistantTools.neighbourJSON(episodes[3], prefix: "next")["next_season"] as? Int == 2)

        let seasons = try AssistantTools.episodesJSON(episodes, season: nil, seriesName: "Show")["seasons"] as? [[String: Any]]
        #expect(seasons?.map { $0["season"] as? Int } == [0, 1, 2])
        let one = try AssistantTools.episodesJSON(episodes, season: 1, seriesName: "Show")["episodes"] as? [[String: Any]]
        #expect(one?.map { $0["title"] as? String } == ["A", "B"])
        #expect(Self.message { try AssistantTools.episodesJSON(episodes, season: 5, seriesName: "Show") } == "No season 5 in Show")
    }

    @Test func subtitleTrackChoice() throws {
        let item = try Self.jellyfin(#"""
            {"id":"m","name":"Film","type":"Movie","mediaSources":[{"id":"src","mediaStreams":[
              {"type":"Subtitle","index":3,"isTextSubtitleStream":true,"language":"ger"},
              {"type":"Subtitle","index":4,"isTextSubtitleStream":true,"language":"eng","title":"Forced"},
              {"type":"Subtitle","index":5,"isTextSubtitleStream":false}]}]}
            """#)
        #expect(try AssistantTools.subtitleTrack(of: item, wanted: 4, playing: nil).stream.index == 4)
        #expect(try AssistantTools.subtitleTrack(of: item, wanted: nil, playing: 3).stream.index == 3)
        #expect(try AssistantTools.subtitleTrack(of: item, wanted: nil, playing: 3).sourceId == "src")
        #expect(Self.message { try AssistantTools.subtitleTrack(of: item, wanted: 5, playing: nil) }?.hasPrefix("Track 5 is not a text subtitle track of Film.") == true)
        #expect(Self.message { try AssistantTools.subtitleTrack(of: item, wanted: nil, playing: nil) }?.hasPrefix("Film has 2 text subtitle tracks") == true)
        let tracks = AssistantTools.trackJSON(try #require(item.mediaSources?.first?.mediaStreams?[1]))
        #expect(tracks["forced"] as? Bool == true && tracks["text"] as? Bool == true)

        let images = try Self.jellyfin(#"{"id":"i","name":"Old","type":"Movie","mediaSources":[{"id":"x","mediaStreams":[{"type":"Subtitle","index":2,"isTextSubtitleStream":false}]}]}"#)
        #expect(Self.message { try AssistantTools.subtitleTrack(of: images, wanted: nil, playing: nil) } == "Old has only image subtitles (no text subtitles).")
        let none = try Self.jellyfin(#"{"id":"n","name":"Silent","type":"Movie"}"#)
        #expect(Self.message { try AssistantTools.subtitleTrack(of: none, wanted: nil, playing: nil) } == "Silent has no media file")
    }
}
