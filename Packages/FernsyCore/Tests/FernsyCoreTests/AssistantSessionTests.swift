import Foundation
import Testing
@testable import FernsyCore

/// The assistant's conversation loop (cloud-assistant 3.1): tool calls run in the app and go back
/// as results, failures leave the conversation as it was, Apple TV keeps no history.
@MainActor
struct AssistantSessionTests {
    /// Answers with the queued replies in turn and records what it was sent.
    final class FakeRelay: AssistantTransport, @unchecked Sendable {
        var replies: [Result<AssistantMessage, AssistantFailure>]
        var sent: [[AssistantMessage]] = []
        init(_ replies: [Result<AssistantMessage, AssistantFailure>]) { self.replies = replies }

        func assistant(messages: [AssistantMessage], context: AssistantContext) async throws -> AssistantReply {
            sent.append(messages)
            let next = replies.removeFirst()
            let usage = AssistantUsage(used: sent.count, limit: 300, renewsAt: Date(timeIntervalSince1970: 0))
            switch next {
            case .success(let message): return AssistantReply(message: message, usage: usage)
            case .failure(let failure): throw failure
            }
        }
    }

    static func answer(_ text: String) -> AssistantMessage { AssistantMessage(role: "assistant", content: text) }
    static func call(_ id: String, _ name: String, _ arguments: String) -> AssistantMessage {
        AssistantMessage(role: "assistant", content: nil, toolCalls: [.init(id: id, function: .init(name: name, arguments: arguments))])
    }

    @Test func toolCallsRunInTheAppAndGoBack() async throws {
        let relay = FakeRelay([.success(Self.call("c1", "play", #"{"item_id":"live:2"}"#)), .success(Self.answer("ZDF läuft."))])
        var ran: [(String, [String: Any])] = []
        let session = AssistantSession(transport: relay, platform: "iPad") { name, arguments in
            ran.append((name, arguments))
            return ["result": "playing"]
        }
        let text = try await session.ask("spiel ZDF")
        #expect(text == "ZDF läuft.")
        #expect(ran.count == 1 && ran[0].0 == "play" && ran[0].1["item_id"] as? String == "live:2")
        let second = try #require(relay.sent.last)
        #expect(second.last?.role == "tool")
        #expect(second.last?.toolCallId == "c1")
        #expect(second.last?.content == #"{"result":"playing"}"#)
        #expect(session.messages.count == 4)
        #expect(session.usage?.used == 2)
    }

    @Test func aFailingToolTellsTheModel() async throws {
        struct Refused: LocalizedError { var errorDescription: String? { "No recordings on this device" } }
        let relay = FakeRelay([.success(Self.call("c1", "schedule_recording", "{}")), .success(Self.answer("Das geht hier nicht."))])
        let session = AssistantSession(transport: relay, platform: "iPhone") { _, _ in throw Refused() }
        _ = try await session.ask("nimm das auf")
        #expect(relay.sent.last?.last?.content == #"{"error":"No recordings on this device"}"#)
    }

    @Test func aFailureLeavesTheConversationAsItWas() async throws {
        let relay = FakeRelay([.success(Self.answer("Hallo.")), .failure(.allowanceUsed(renewsAt: nil))])
        let session = AssistantSession(transport: relay, platform: "Mac") { _, _ in [:] }
        _ = try await session.ask("hallo")
        await #expect(throws: AssistantFailure.allowanceUsed(renewsAt: nil)) { try await session.ask("noch was") }
        #expect(session.messages.count == 2)
    }

    @Test func appleTVKeepsNoHistory() async throws {
        let relay = FakeRelay([.success(Self.answer("Eins.")), .success(Self.answer("Zwei."))])
        let session = AssistantSession(transport: relay, platform: "Apple TV") { _, _ in [:] }
        _ = try await session.ask("eins", keepHistory: false)
        _ = try await session.ask("zwei", keepHistory: false)
        #expect(relay.sent.last?.count == 1)
        #expect(relay.sent.last?.first?.content == "zwei")
    }

    @Test func messagesUseTheRelaysKeys() throws {
        let json = String(decoding: try JSONEncoder().encode(Self.call("c1", "play", "{}")), as: UTF8.self)
        #expect(json.contains(#""tool_calls""#))
        let tool = String(decoding: try JSONEncoder().encode(AssistantMessage.tool("c1", "{}")), as: UTF8.self)
        #expect(tool.contains(#""tool_call_id":"c1""#))
    }
}
