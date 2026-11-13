import FernsyCore
import Foundation
import Testing
@testable import FernsyPlayer

/// Planned recordings and "IPTV only with VPN" (vpn-guard 5.1): without a VPN a due recording
/// stays planned, starts when the VPN connects, and is missed with that reason when it does not.
@MainActor
@Suite(.serialized)
struct VPNGuardRecorderTests {
    final class Host: RecorderHost {
        let tuners = TunerPool()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-\(UUID().uuidString)")
        var asked: [Int] = []
        func liveURL(_ channelId: Int) -> URL? {
            asked.append(channelId)
            return URL(string: "https://recorder.test/live/demo/demo/\(channelId).ts")
        }
        func playForRecording(_ channelId: Int) {}
        func ask(title: String, message: String, confirm: String, cancel: String, timeout: TimeInterval, timeoutAnswer: Bool) async -> Bool { timeoutAnswer }
        func recordingsStore(accountKey: String) -> URL { root.appendingPathComponent("store") }
        var recordingsFolder: URL { root.appendingPathComponent("files") }
        func removeRecordingFile(_ url: URL) {}
        func keepAwake(reason: String?) {}
        var dropsMissingRecordings: Bool { false }
    }

    final class Network: @unchecked Sendable {
        var vpn = false
    }

    let host = Host()
    let network = Network()
    let recorder = Recorder()

    init() throws {
        HTTPByteSource.testProtocolClasses = [VPNGuardSourceTests.Provider.self]
        VPNGuardSourceTests.Provider.reset("recorder.test")
        let defaults = try #require(UserDefaults(suiteName: "recorder-gate-\(UUID().uuidString)"))
        defaults.set(true, forKey: ProviderGate.enabledKey)
        let network = network
        recorder.gate = ProviderGate(defaults: defaults) { VPNProbe.current(faked: network.vpn) }
        recorder.host = host
        recorder.activate(accountKey: "test")
    }

    private func plan(endsIn seconds: TimeInterval) throws -> UUID {
        let channel = try JSONDecoder().decode(LiveChannel.self, from: Data(#"{"stream_id": 101, "name": "Demo One"}"#.utf8))
        let now = Date()
        let entry = EPGEntry(id: "1", title: "Evening News", description: "", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(seconds))
        recorder.schedule(entry, on: channel, padding: (0, 0))
        return try #require(recorder.recordings.first?.id)
    }

    private func status(_ id: UUID) -> Recording.Status? { recorder.recordings.first { $0.id == id }?.status }

    @Test func aDueRecordingStaysPlannedWithoutAVPN() throws {
        let id = try plan(endsIn: 60)
        recorder.tick()
        recorder.tick()
        #expect(status(id) == .scheduled)
        #expect(VPNGuardSourceTests.Provider.requests(to: "recorder.test") == 0)
        recorder.activate(accountKey: nil)
    }

    @Test func itStartsWhenTheVPNConnects() async throws {
        let id = try plan(endsIn: 60)
        recorder.tick()
        #expect(status(id) == .scheduled)
        network.vpn = true
        recorder.tick()
        for _ in 0..<100 where status(id) != .recording { try await Task.sleep(for: .milliseconds(50)) }
        #expect(status(id) == .recording)
        #expect(recorder.recordings.first?.error == nil)
        recorder.activate(accountKey: nil)
    }

    @Test func withoutAVPNUntilTheEndItIsMissedWithTheReason() async throws {
        let id = try plan(endsIn: 1)
        recorder.tick()
        #expect(status(id) == .scheduled)
        try await Task.sleep(for: .milliseconds(1200))
        recorder.tick()
        #expect(status(id) == .missed)
        #expect(recorder.recordings.first?.error == ProviderGateError.vpnRequired.localizedDescription)
        #expect(VPNGuardSourceTests.Provider.requests(to: "recorder.test") == 0)
        recorder.activate(accountKey: nil)
    }

    /// Missed because Fernsy was not open keeps its old text: no reason is stored.
    @Test func missedWithoutAWaitHasNoReason() async throws {
        network.vpn = true
        let channel = try JSONDecoder().decode(LiveChannel.self, from: Data(#"{"stream_id": 102, "name": "Demo Two"}"#.utf8))
        let entry = EPGEntry(id: "2", title: "Over", description: "", start: Date().addingTimeInterval(-120), end: Date().addingTimeInterval(-1))
        recorder.schedule(entry, on: channel, padding: (0, 0))
        recorder.tick()
        #expect(recorder.recordings.first?.status == .missed)
        #expect(recorder.recordings.first?.error == nil)
        recorder.activate(accountKey: nil)
    }
}
