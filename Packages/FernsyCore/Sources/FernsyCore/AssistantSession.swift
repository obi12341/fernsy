import Foundation

/// One message of an assistant conversation, in the chat completions form the Fernsy Cloud relay
/// takes and returns (cloud-assistant design 1).
public struct AssistantMessage: Codable, Equatable, Sendable {
    public struct ToolCall: Codable, Equatable, Sendable {
        public struct Function: Codable, Equatable, Sendable {
            public var name: String
            /// The arguments as a JSON object in a string, as the model writes them.
            public var arguments: String
        }
        public var id: String
        public var type = "function"
        public var function: Function
    }

    public var role: String
    public var content: String?
    public var toolCalls: [ToolCall]?
    public var toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    public static func user(_ text: String) -> AssistantMessage { AssistantMessage(role: "user", content: text) }
    public static func tool(_ id: String, _ result: String) -> AssistantMessage { AssistantMessage(role: "tool", content: result, toolCallId: id) }

    public init(role: String, content: String?, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

/// Facts about the device the relay adds to the prompt: time, zone, language, platform.
public struct AssistantContext: Codable, Equatable, Sendable {
    public var now: String
    public var timeZone: String
    public var locale: String
    public var platform: String

    public static func current(platform: String, now: Date = Date()) -> AssistantContext {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return AssistantContext(now: formatter.string(from: now), timeZone: TimeZone.current.identifier,
                                locale: Locale.preferredLanguages.first ?? "en", platform: platform)
    }
}

/// The month's allowance as the relay reports it.
public struct AssistantUsage: Codable, Equatable, Sendable {
    public var used: Int
    public var limit: Int
    public var renewsAt: Date
}

public struct AssistantReply: Decodable, Equatable, Sendable {
    public var message: AssistantMessage
    public var usage: AssistantUsage
}

/// Why the assistant cannot answer.
public enum AssistantFailure: Error, Equatable {
    case noSubscription
    case allowanceUsed(renewsAt: Date?)
    case rateLimited
    /// The relay has no provider key, or the provider failed.
    case unavailable
    case tooLong
    case network(String)
    case server(status: Int, code: String)
}

/// Sends one round to the relay; `CloudClient` in the apps, a stand-in in tests.
public protocol AssistantTransport: Sendable {
    func assistant(messages: [AssistantMessage], context: AssistantContext) async throws -> AssistantReply
}

/// A conversation with the assistant (cloud-assistant): sends the user's request, runs the tools
/// the model asks for through `runTool` (the app's model, which holds the catalog and plays), and
/// sends their results until the model answers. Tool results are strings of JSON; a failing tool
/// reports its error to the model, which can explain it or try another way.
@MainActor
public final class AssistantSession {
    public typealias ToolRunner = @MainActor (_ name: String, _ arguments: [String: Any]) async throws -> [String: Any]

    public private(set) var messages: [AssistantMessage] = []
    public private(set) var usage: AssistantUsage?
    private let transport: AssistantTransport
    private let platform: String
    private let runTool: ToolRunner
    /// Rounds per request before the app stops asking (the relay caps tool rounds too).
    private let maxRounds = 12

    public init(transport: AssistantTransport, platform: String, runTool: @escaping ToolRunner) {
        self.transport = transport
        self.platform = platform
        self.runTool = runTool
    }

    /// Asks and returns the answer's text. `keepHistory` false (Apple TV) starts a new
    /// conversation for every request.
    public func ask(_ text: String, keepHistory: Bool = true) async throws -> String {
        if !keepHistory { messages = [] }
        let start = messages.count
        messages.append(.user(text))
        do {
            for _ in 0..<maxRounds {
                let reply = try await transport.assistant(messages: messages, context: .current(platform: platform))
                usage = reply.usage
                messages.append(reply.message)
                guard let calls = reply.message.toolCalls, !calls.isEmpty else { return reply.message.content ?? "" }
                for call in calls { messages.append(.tool(call.id, await result(of: call))) }
            }
            return ""
        } catch {
            // A failed request leaves the conversation as it was, so asking again works.
            messages.removeSubrange(start...)
            throw error
        }
    }

    public func reset() { messages = [] }

    private func result(of call: AssistantMessage.ToolCall) async -> String {
        let data = Data(call.function.arguments.utf8)
        let arguments = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let value: [String: Any]
        do {
            value = try await runTool(call.function.name, arguments)
        } catch {
            value = ["error": error.localizedDescription]
        }
        let json = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: json, as: UTF8.self)
    }
}

extension CloudClient: AssistantTransport {}
