import Foundation
import Testing
@testable import FernsyCore

/// The assistant as the apps show it (cloud-assistant 3.2–3.6): nothing is sent without consent,
/// refusals become short texts, the Apple TV keeps one request, the usage stays for Settings, and
/// a tool's question waits for the user's answer.
@MainActor
struct AssistantModelTests {
    typealias Relay = AssistantSessionTests.FakeRelay

    private func model(_ relay: Relay, keepHistory: Bool = true) -> (AssistantModel, UserDefaults) {
        let name = "AssistantModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let assistant = AssistantModel(cloud: nil, platform: "iPad", keepHistory: keepHistory, transport: relay, defaults: defaults) { _, _ in ["result": "ok"] }
        return (assistant, defaults)
    }

    @Test func nothingIsSentWithoutConsent() async {
        let relay = Relay([.success(AssistantSessionTests.answer("Hallo"))])
        let (assistant, defaults) = model(relay)
        #expect(!assistant.hasConsent)
        assistant.draft = "was läuft?"
        await assistant.send()
        #expect(relay.sent.isEmpty)
        #expect(assistant.entries.isEmpty)

        assistant.agree()
        #expect(defaults.bool(forKey: AssistantModel.consentKey))
        await assistant.send()
        #expect(relay.sent.count == 1)

        assistant.withdrawConsent()
        #expect(!assistant.hasConsent)
        #expect(!defaults.bool(forKey: AssistantModel.consentKey))
    }

    @Test func answersAndRefusalsBecomeEntries() async {
        let relay = Relay([.success(AssistantSessionTests.answer("ZDF läuft.")), .failure(.rateLimited)])
        let (assistant, defaults) = model(relay)
        assistant.agree()
        for text in ["spiel ZDF", "und jetzt?"] {
            assistant.draft = text
            await assistant.send()
        }
        #expect(assistant.entries.map(\.kind) == [.request, .answer, .request, .failure])
        #expect(assistant.entries[1].text == "ZDF läuft.")
        #expect(assistant.entries[3].text == AssistantModel.describe(AssistantFailure.rateLimited))
        #expect(assistant.draft.isEmpty)
        #expect(assistant.usage?.used == 1)
        #expect(defaults.data(forKey: AssistantModel.usageKey) != nil)
    }

    @Test func appleTVShowsOneRequest() async {
        let relay = Relay([.success(AssistantSessionTests.answer("Eins")), .success(AssistantSessionTests.answer("Zwei"))])
        let (assistant, _) = model(relay, keepHistory: false)
        assistant.agree()
        for text in ["a", "b"] {
            assistant.draft = text
            await assistant.send()
        }
        #expect(assistant.entries.map(\.text) == ["b", "Zwei"])
        #expect(relay.sent.last?.count == 1)
        #expect(assistant.lastReply?.text == "Zwei")
    }

    @Test func allowanceEndNamesTheRenewalDate() {
        let date = Date(timeIntervalSince1970: 1_801_000_000)
        let text = AssistantModel.describe(AssistantFailure.allowanceUsed(renewsAt: date))
        #expect(text.contains(date.formatted(date: .long, time: .omitted)))
        #expect(AssistantModel.describe(AssistantFailure.rateLimited) != AssistantModel.describe(AssistantFailure.unavailable))
        #expect(AssistantModel.describe(AssistantFailure.server(status: 500, code: "x")) == AssistantModel.describe(AssistantFailure.unavailable))
    }

    @Test func questionWaitsForTheAnswer() async {
        let (assistant, _) = model(Relay([]))
        async let answer = assistant.confirm("Remove it?")
        while assistant.question == nil { await Task.yield() }
        #expect(assistant.question == "Remove it?")
        assistant.answerQuestion(true)
        #expect(await answer)
        #expect(assistant.question == nil)
    }
}
