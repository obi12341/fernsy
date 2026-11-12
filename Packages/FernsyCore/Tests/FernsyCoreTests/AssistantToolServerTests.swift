import Foundation
import Synchronization
import Testing
@testable import FernsyCore
@testable import FernsyShared

/// Fernsy Server in the recording tools (server-recording-everywhere design 4): `where`, the ids
/// and JSON of server orders, and ordering, listing and cancelling them on a fake control service.
@MainActor
struct AssistantToolServerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func paired(_ control: FakeControl) async throws -> (ServerModel, ControlKey) {
        let stored = Mutex<ControlKey?>(ControlKey())
        let keys = ControlKeyStore(backing: nil, loadLocal: { stored.withLock { $0 } }, saveLocal: { key in stored.withLock { $0 = key } })
        let model = ServerModel(api: control, keys: keys, cloudKeys: CloudKeyStore(backing: nil, loadLocal: { nil }, saveLocal: { _ in }))
        let key = try #require(await keys.key())
        _ = try await control.put(ControlServerStatus(lastContact: Date(), version: "test"), kind: .server, id: "status", key: key)
        return (model, key)
    }

    func show(startsIn: TimeInterval, title: String = "News") -> ControlOrder {
        ControlOrder(channelId: 7, channelName: "Seven", title: title, showStart: now + startsIn, showEnd: now + startsIn + 1800,
                     padBefore: 600, padAfter: 300, createdBy: "iPad")
    }

    @Test func whereIsOptionalAndChecked() throws {
        #expect(try AssistantTools.place([:]) == nil)
        #expect(try AssistantTools.place(["where": "server"]) == .server)
        #expect(try AssistantTools.place(["where": "device"]) == .device)
        #expect(throws: AssistantTools.ToolError.self) { try AssistantTools.place(["where": "cloud"]) }
        let schedule = try #require(AssistantTools.definitions.first { $0["name"] as? String == "schedule_recording" })
        let properties = try #require((schedule["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        #expect((properties["where"] as? [String: Any])?["enum"] as? [String] == ["device", "server"])
    }

    @Test func serverOrderIdsAndJSON() {
        #expect(AssistantTools.serverOrderID(AssistantTools.serverRecordingID("abc")) == "abc")
        #expect(AssistantTools.serverOrderID("4A7D3C52-0000-4000-8000-000000000000") == nil)
        let row = ServerModel.Order(id: "abc", order: show(startsIn: 3600), state: ControlOrderState(phase: .failed, reason: .noStream))
        let json = AssistantTools.serverOrderJSON(row)
        #expect(json["recording_id"] as? String == "server:abc")
        #expect(json["where"] as? String == "server")
        #expect(json["status"] as? String == "failed")
        #expect(json["reason"] as? String == ServerText.reason(.noStream))
        #expect(json["record_start"] as? String == AssistantTools.iso(now + 3000))
        #expect(json["record_end"] as? String == AssistantTools.iso(now + 3600 + 1800 + 300))
        #expect(json["ordered_by"] as? String == "iPad")
        #expect(AssistantTools.serverStatus(nil) == "sent")
    }

    @Test func orderingSaysWhereAndWhetherItIsNew() async throws {
        let control = FakeControl()
        let (server, key) = try await paired(control)
        func order(_ show: ControlOrder, streams: Int = 0) async throws -> [String: Any] {
            try await AssistantTools.orderOnServer(server) { () async throws(ServerModel.OrderFailure) -> (order: ServerModel.Order, isNew: Bool) in
                try await server.place(show, streamsInUse: streams, limit: 1, now: self.now)
            }
        }
        let first = try await order(show(startsIn: 7200))
        #expect(first["result"] as? String == "ordered")
        #expect(first["where"] as? String == "server")
        #expect(((first["recording"] as? [String: Any])?["recording_id"] as? String)?.hasPrefix("server:") == true)
        #expect(first["notice"] == nil)
        #expect(try await order(show(startsIn: 7200))["result"] as? String == "already_ordered")
        #expect(control.orderCount(key) == 1)
        // The show runs and this device holds the account's only stream.
        let refused = try await order(show(startsIn: -300, title: "Now"), streams: 1)
        #expect(refused["result"] as? String == "refused")
        #expect((refused["reason"] as? String)?.isEmpty == false)
        #expect(control.orderCount(key) == 1)
        // A server that has been away for a while: ordered, with a note.
        _ = try await control.put(ControlServerStatus(lastContact: Date().addingTimeInterval(-3600), version: "test"), kind: .server, id: "status", key: key)
        #expect(try await order(show(startsIn: 10800, title: "Later"))["notice"] as? String == ServerText.offline)
    }

    @Test func orderingWithoutAServerNamesSettings() async throws {
        let control = FakeControl()
        let server = ServerModel(api: control, keys: ControlKeyStore(backing: nil, loadLocal: { nil }, saveLocal: { _ in }),
                                 cloudKeys: CloudKeyStore(backing: nil, loadLocal: { nil }, saveLocal: { _ in }))
        do {
            _ = try await AssistantTools.orderOnServer(server) { () async throws(ServerModel.OrderFailure) -> (order: ServerModel.Order, isNew: Bool) in
                try await server.place(self.show(startsIn: 7200), streamsInUse: 0, limit: 1, now: self.now)
            }
            Issue.record("ordered without a server")
        } catch {
            #expect(error.localizedDescription.contains("settings"))
        }
        #expect(await AssistantTools.serverRecordings(server, status: "all").isEmpty)
    }

    @Test func listingAndCancelling() async throws {
        let control = FakeControl()
        let (server, key) = try await paired(control)
        _ = try await control.put(show(startsIn: 7200, title: "Later"), kind: .order, id: "later", key: key)
        _ = try await control.put(show(startsIn: -300, title: "Now"), kind: .order, id: "now", key: key)
        _ = try await control.put(ControlOrderState(phase: .recording), kind: .state, id: "now", key: key)
        _ = try await control.put(show(startsIn: -7200, title: "Earlier"), kind: .order, id: "earlier", key: key)
        _ = try await control.put(ControlOrderState(phase: .done), kind: .state, id: "earlier", key: key)
        // Done orders are cloud recordings, not listed; "scheduled" takes what the server has not seen yet.
        let all = await AssistantTools.serverRecordings(server, status: "all")
        #expect(Set(all.compactMap { $0["recording_id"] as? String }) == ["server:later", "server:now"])
        #expect(await AssistantTools.serverRecordings(server, status: "scheduled").map { $0["title"] as? String } == ["Later"])
        #expect(await AssistantTools.serverRecordings(server, status: "recording").map { $0["title"] as? String } == ["Now"])
        // A running order stays, an unconfirmed one too.
        await #expect(throws: AssistantTools.ToolError.self) { try await AssistantTools.cancelServerOrder("now", server: server) { _ in true } }
        await #expect(throws: AssistantTools.ToolError.self) { try await AssistantTools.cancelServerOrder("nothing", server: server) { _ in true } }
        let asked = Mutex<[String]>([])
        let kept = try await AssistantTools.cancelServerOrder("later", server: server) { question in asked.withLock { $0.append(question) }; return false }
        #expect(kept["result"] as? String == "kept")
        #expect(asked.withLock { $0.first }?.contains("Later") == true)
        #expect(control.orderCount(key) == 3)
        let cancelled = try await AssistantTools.cancelServerOrder("later", server: server) { _ in true }
        #expect(cancelled["result"] as? String == "cancelled")
        #expect(cancelled["recording_id"] as? String == "server:later")
        #expect(control.orderCount(key) == 2)
    }
}
