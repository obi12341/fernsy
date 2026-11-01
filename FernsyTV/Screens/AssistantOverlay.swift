import FernsyCore
import SwiftUI

/// The assistant on the Apple TV (cloud-assistant design 7): one request in a text field (tvOS'
/// keyboard, with dictation), the answer, and its action carried out; no chat history. Opened
/// from Start and the live player's tabs; Back closes it. Without a subscription it offers
/// Fernsy Cloud, before the first request it asks for consent.
struct AssistantOverlay: View {
    @EnvironmentObject private var model: TVModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let assistant = model.assistant
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 30) {
                Label("Assistant", systemImage: "sparkles").font(.system(size: 34, weight: .bold))
                if !assistant.isAvailable {
                    offer
                } else if !assistant.hasConsent {
                    consent
                } else {
                    request(assistant)
                }
            }
            .padding(56)
            .frame(width: 1240, alignment: .leading)
            .background(TVTheme.background.opacity(0.94), in: .rect(cornerRadius: 40))
            .foregroundStyle(TVTheme.text)
        }
        .focusSection()
        .onExitCommand { model.showsAssistant = false }
        // Closed while a tool asks: nothing is removed.
        .onDisappear { if !model.showsAssistant && assistant.question != nil { assistant.answerQuestion(false) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant.overlay")
        .alert(assistant.question ?? "", isPresented: Binding(get: { assistant.question != nil },
                                                             set: { if !$0 { assistant.answerQuestion(false) } })) {
            Button("Remove", role: .destructive) { assistant.answerQuestion(true) }
            Button("Keep", role: .cancel) { assistant.answerQuestion(false) }
        }
    }

    @ViewBuilder private func request(_ assistant: AssistantModel) -> some View {
        HStack(spacing: 24) {
            TVTextEntry(text: Binding(get: { assistant.draft }, set: { assistant.draft = $0 }),
                        prompt: String(localized: "What would you like to watch?"),
                        onSubmit: { Task { await assistant.send() } }) {
                HStack(spacing: 16) {
                    Image(systemName: "mic.fill").opacity(0.6)
                    Text(verbatim: assistant.draft.isEmpty ? String(localized: "What would you like to watch?") : assistant.draft)
                        .opacity(assistant.draft.isEmpty ? 0.6 : 1)
                        .lineLimit(1)
                }
                .font(.system(size: 28, weight: .medium))
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            }
            .buttonStyle(TVTileStyle(radius: 45, scale: 1.02))
            .focused($fieldFocused)
            .accessibilityIdentifier("assistant.field")
            Button { Task { await assistant.send() } } label: { Text("Ask") }
                .buttonStyle(ActionButtonStyle())
                .disabled(assistant.isWaiting)
                .accessibilityIdentifier("assistant.send")
        }
        .defaultFocus($fieldFocused, true)
        .onAppear { fieldFocused = true }
        if let asked = assistant.entries.first(where: { $0.kind == .request }) {
            Text(verbatim: asked.text).font(.system(size: 24)).foregroundStyle(TVTheme.secondary)
        }
        if assistant.isWaiting {
            ProgressView().accessibilityIdentifier("assistant.waiting")
        } else if let reply = assistant.lastReply {
            Text(verbatim: reply.text)
                .font(.system(size: 30))
                .foregroundStyle(reply.kind == .failure ? TVTheme.warning : TVTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("assistant.answer")
        }
    }

    @ViewBuilder private var consent: some View {
        Text(verbatim: AssistantModel.consentText)
            .font(.system(size: 24)).foregroundStyle(TVTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 24) {
            Button("Agree") { model.assistant.agree() }
                .buttonStyle(TVPillStyle())
                .accessibilityIdentifier("assistant.consent.agree")
            Button("Not Now") { model.showsAssistant = false }
                .buttonStyle(TVPillStyle(prominent: false))
        }
    }

    @ViewBuilder private var offer: some View {
        Text("The assistant is part of Fernsy Cloud.").font(.system(size: 26, weight: .semibold))
        ForEach(CloudModel.offerParts, id: \.self) { part in
            Label { Text(verbatim: part) } icon: { Image(systemName: "checkmark") }
                .font(.system(size: 24)).foregroundStyle(TVTheme.secondary)
        }
        HStack(spacing: 24) {
            Button {
                Task { await model.cloud.purchase() }
            } label: {
                if let offer = model.cloud.offer { Text("Subscribe · \(offer.price)") } else { Text("Subscribe") }
            }
            .buttonStyle(TVPillStyle())
            .disabled(model.cloud.isPurchasing)
            .accessibilityIdentifier("assistant.subscribe")
            Button("Restore Purchases") { Task { await model.cloud.restore() } }
                .buttonStyle(TVPillStyle(prominent: false))
                .disabled(model.cloud.isPurchasing)
        }
    }
}
