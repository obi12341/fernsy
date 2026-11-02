import FernsyShared
import Foundation
import Testing
@testable import FernsyServer

/// When the server writes its status (control-fewer-writes).
struct StatusReportTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func status(at time: Date, free: Int64 = 1_000, running: [String] = []) -> ControlServerStatus {
        ControlServerStatus(lastContact: time, version: "2.3.0", freeBytes: free, running: running)
    }

    @Test func theFirstReportGoesOutAtOnce() {
        #expect(StatusReport.isDue(status(at: start), lastSent: nil, lastSentAt: .distantPast, now: start))
    }

    @Test func aQuietPollSendsNothing() {
        let sent = status(at: start)
        let later = start.addingTimeInterval(30)
        // Only last contact and free space differ.
        #expect(!StatusReport.isDue(status(at: later, free: 900), lastSent: sent, lastSentAt: start, now: later))
    }

    @Test func aStartedRecordingGoesOutOnTheNextPoll() {
        let sent = status(at: start)
        let later = start.addingTimeInterval(30)
        #expect(StatusReport.isDue(status(at: later, running: ["o1"]), lastSent: sent, lastSentAt: start, now: later))
    }

    @Test func theHeartbeatGoesOutAfterFiveMinutes() {
        let sent = status(at: start)
        let almost = start.addingTimeInterval(StatusReport.heartbeat - 30)
        let due = start.addingTimeInterval(StatusReport.heartbeat)
        #expect(!StatusReport.isDue(status(at: almost), lastSent: sent, lastSentAt: start, now: almost))
        #expect(StatusReport.isDue(status(at: due), lastSent: sent, lastSentAt: start, now: due))
        // Inside the apps' 10 minutes, with room for one missed report.
        #expect(StatusReport.heartbeat * 2 <= 600)
    }
}
