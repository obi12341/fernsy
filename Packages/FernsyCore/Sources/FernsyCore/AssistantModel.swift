import Foundation
import Observation

/// The assistant as the apps show it (cloud-assistant), shared by the Mac, iOS and Apple TV: the
/// consent on this device, the request in flight, the session's requests and answers, refusals as
/// short texts, the month's usage, and the question before a tool removes something.
@MainActor
@Observable
public final class AssistantModel {
    public struct Entry: Identifiable, Equatable, Sendable {
        public enum Kind: Sendable { case request, answer, failure }
        public let id = UUID()
        public var kind: Kind
        public var text: String
    }

    /// UserDefaults keys: the consent (per device, design 8) and the last usage the relay reported.
    public static let consentKey = "assistant.consent"
    static let usageKey = "assistant.usage"

    public private(set) var entries: [Entry] = []
    public private(set) var isWaiting = false
    /// The text field's content.
    public var draft = ""
    public private(set) var hasConsent: Bool
    /// The month's requests as the relay last reported them (Settings › Fernsy Cloud).
    public private(set) var usage: AssistantUsage?
    /// A tool's question before it removes something (design 5), until the user answers it.
    public private(set) var question: String?

    @ObservationIgnored private weak var cloud: CloudModel?
    @ObservationIgnored private let keepHistory: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var session: AssistantSession!
    @ObservationIgnored private var answer: CheckedContinuation<Bool, Never>?

    /// `keepHistory` false (Apple TV): one request at a time, no conversation.
    public init(cloud: CloudModel?, platform: String, keepHistory: Bool = true, transport: AssistantTransport? = nil,
                defaults: UserDefaults = .standard, runTool: @escaping AssistantSession.ToolRunner) {
        self.cloud = cloud
        self.keepHistory = keepHistory
        self.defaults = defaults
        hasConsent = defaults.bool(forKey: Self.consentKey)
        usage = defaults.data(forKey: Self.usageKey).flatMap { try? JSONDecoder().decode(AssistantUsage.self, from: $0) }
        #if DEBUG
        // IPTV_ASSISTANT_CONSENT=1 agrees for this run, =0 starts without the stored consent.
        switch ProcessInfo.processInfo.environment["IPTV_ASSISTANT_CONSENT"] {
        case "1": hasConsent = true
        case "0": withdrawConsent()
        default: break
        }
        #endif
        let relay = transport ?? Self.stub ?? cloud?.client ?? CloudClient.live()
        session = AssistantSession(transport: relay, platform: platform, runTool: runTool)
    }

    /// With an active subscription the assistant answers; without one the apps offer Fernsy Cloud
    /// and send nothing (spec "Without subscription"). Without a CloudModel (tests) it is available.
    public var isAvailable: Bool { Self.stub != nil || (cloud.map(\.hasSubscription) ?? true) }

    /// "12 of 300 this month", while the reported month lasts.
    public var usageText: String? {
        guard let usage, usage.renewsAt > .now else { return nil }
        return String(localized: "\(usage.used) of \(usage.limit) this month", bundle: .module)
    }

    // MARK: Consent

    public func agree() {
        defaults.set(true, forKey: Self.consentKey)
        hasConsent = true
    }

    /// Settings › Fernsy Cloud: the consent screen shows again before the next request.
    public func withdrawConsent() {
        defaults.removeObject(forKey: Self.consentKey)
        hasConsent = false
    }

    // MARK: Requests

    /// Sends the draft (only with consent) and adds the answer or the refusal to `entries`.
    public func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting, hasConsent, isAvailable else { return }
        draft = ""
        if !keepHistory { entries = [] }
        entries.append(Entry(kind: .request, text: text))
        isWaiting = true
        defer { isWaiting = false }
        do {
            let answer = try await session.ask(text, keepHistory: keepHistory)
            entries.append(Entry(kind: .answer, text: answer.isEmpty ? String(localized: "Done.", bundle: .module) : answer))
        } catch {
            entries.append(Entry(kind: .failure, text: Self.describe(error)))
        }
        if let latest = session.usage, latest != usage {
            usage = latest
            defaults.set(try? JSONEncoder().encode(latest), forKey: Self.usageKey)
        }
    }

    /// A new conversation (Mac, iOS).
    public func reset() {
        guard !isWaiting else { return }
        entries = []
        session.reset()
    }

    /// The latest answer or refusal (Apple TV shows only that).
    public var lastReply: Entry? { entries.last { $0.kind != .request } }

    // MARK: Confirmation

    /// Asks `text` in the app's assistant UI and waits for the answer (design 5).
    public func confirm(_ text: String) async -> Bool {
        answer?.resume(returning: false)
        question = text
        return await withCheckedContinuation { answer = $0 }
    }

    public func answerQuestion(_ yes: Bool) {
        question = nil
        answer?.resume(returning: yes)
        answer = nil
    }

    // MARK: Texts

    /// A refusal or failure in a short sentence for the user.
    public static func describe(_ error: Error) -> String {
        switch error as? AssistantFailure {
        case .noSubscription?:
            return String(localized: "The assistant needs an active Fernsy Cloud subscription.", bundle: .module)
        case .allowanceUsed(let renewsAt)?:
            guard let renewsAt else { return String(localized: "This month’s assistant requests are used up.", bundle: .module) }
            let date = renewsAt.formatted(date: .long, time: .omitted)
            return String(localized: "This month’s assistant requests are used up. They renew on \(date).", bundle: .module)
        case .rateLimited?:
            return String(localized: "That was a lot of requests at once. Please wait a moment and ask again.", bundle: .module)
        case .tooLong?:
            return String(localized: "This is too long for the assistant. Please start a new conversation or ask more briefly.", bundle: .module)
        case .network?:
            return String(localized: "The assistant cannot be reached. Please check the connection.", bundle: .module)
        case .unavailable?, .server?, nil:
            return String(localized: "The assistant is not available right now. Please try again later.", bundle: .module)
        }
    }

    /// What the consent screen says (spec "Consent before the first request").
    public static var consentText: String {
        String(localized: "To answer, Fernsy sends your request and the conversation to OpenRouter, which passes them to the model Claude by Anthropic. With them go the parts of your channels, guide, movies and series, favorites and recently watched items that a request needs. Fernsy Cloud only passes them on and keeps none of it. Nothing is sent before you agree, and you can withdraw your consent in Settings › Fernsy Cloud.", bundle: .module)
    }

    // MARK: Stand-in relay

    /// Debug builds with `IPTV_ASSISTANT_STUB=1`: a relay without network for UI tests.
    static var stub: AssistantTransport? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_ASSISTANT_STUB"] == "1" { return AssistantStub() }
        #endif
        return nil
    }
}

#if DEBUG
/// Answers deterministically without the relay (`IPTV_ASSISTANT_STUB=1`): a request naming ZDF or
/// the demo's first channel plays `live:101`, then answers; anything else gets a fixed answer.
struct AssistantStub: AssistantTransport {
    func assistant(messages: [AssistantMessage], context: AssistantContext) async throws -> AssistantReply {
        try await Task.sleep(for: .milliseconds(300))
        let usage = AssistantUsage(used: messages.filter { $0.role == "user" }.count, limit: 300,
                                   renewsAt: Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
        let request = (messages.last { $0.role == "user" }?.content ?? "").lowercased()
        let message: AssistantMessage
        if messages.last?.role == "tool" {
            message = AssistantMessage(role: "assistant", content: "Nordlicht 1 HD is playing.")
        } else if request.contains("zdf") || request.contains("nordlicht") {
            message = AssistantMessage(role: "assistant", content: nil, toolCalls: [
                .init(id: "stub-play", function: .init(name: "play", arguments: #"{"item_id":"live:101"}"#)),
            ])
        } else {
            message = AssistantMessage(role: "assistant", content: "I help with Fernsy: channels, the guide, movies, series and recordings.")
        }
        return AssistantReply(message: message, usage: usage)
    }
}
#endif
