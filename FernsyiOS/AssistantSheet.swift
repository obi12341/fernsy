import FernsyCore
import SwiftUI

/// The assistant on iPad and iPhone (cloud-assistant): the session's conversation and a text
/// field (the keyboard's dictation works in it). Actions run at once; for the player the sheet
/// closes. Without a subscription it offers Fernsy Cloud, before the first request it asks for
/// consent, and before a tool removes something it asks.
struct AssistantSheet: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let assistant = model.assistant
        NavigationStack {
            Group {
                if !assistant.isAvailable {
                    offer
                } else if !assistant.hasConsent {
                    consent(assistant)
                } else {
                    conversation(assistant)
                }
            }
            .background(TVTheme.background.ignoresSafeArea())
            .navigationTitle(Text("Assistant"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if assistant.hasConsent && !assistant.entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Conversation", systemImage: "square.and.pencil") { assistant.reset() }
                            .disabled(assistant.isWaiting)
                    }
                }
            }
        }
        .alert(assistant.question ?? "", isPresented: Binding(get: { assistant.question != nil },
                                                             set: { if !$0 { assistant.answerQuestion(false) } })) {
            Button("Remove", role: .destructive) { assistant.answerQuestion(true) }
            Button("Keep", role: .cancel) { assistant.answerQuestion(false) }
        }
        .preferredColorScheme(.dark)
        // Closed while a tool asks: nothing is removed.
        .onDisappear { if assistant.question != nil { assistant.answerQuestion(false) } }
    }

    private func conversation(_ assistant: AssistantModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if assistant.entries.isEmpty {
                        Text("Ask for a channel, a show, a movie or a recording – typed or dictated.")
                            .foregroundStyle(TVTheme.secondary)
                    }
                    ForEach(assistant.entries) { entry in
                        Bubble(entry: entry).id(entry.id)
                    }
                    if assistant.isWaiting {
                        ProgressView().id("waiting").accessibilityIdentifier("assistant.waiting")
                    }
                }
                .padding(16)
            }
            .onChange(of: assistant.entries.count) {
                withAnimation { proxy.scrollTo(assistant.entries.last?.id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                TextField("Ask Fernsy", text: Binding(get: { assistant.draft }, set: { assistant.draft = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .focused($fieldFocused)
                    .onSubmit { Task { await assistant.send() } }
                    .accessibilityIdentifier("assistant.field")
                Button { Task { await assistant.send() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(assistant.isWaiting || assistant.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("Ask"))
                .accessibilityIdentifier("assistant.send")
            }
            .padding(12)
            .background(.bar)
        }
        .onAppear { fieldFocused = true }
    }

    private func consent(_ assistant: AssistantModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Before the first request", systemImage: "hand.raised").font(.title3.bold())
                Text(verbatim: AssistantModel.consentText).foregroundStyle(TVTheme.secondary)
                Button { assistant.agree() } label: { Text("Agree").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("assistant.consent.agree")
                Button { dismiss() } label: { Text("Not Now").frame(maxWidth: .infinity) }
                    .controlSize(.large)
            }
            .padding(20)
        }
    }

    private var offer: some View {
        let cloud = model.cloud
        return Form {
            Section {
                Text("The assistant is part of Fernsy Cloud.").font(.headline)
                CloudOfferParts()
            }
            Section {
                if let offer = cloud.offer {
                    Text(verbatim: "\(offer.name) · \(offer.price)")
                }
                Button("Subscribe") { Task { await cloud.purchase() } }
                    .disabled(cloud.isPurchasing)
                    .accessibilityIdentifier("assistant.subscribe")
                Button("Restore Purchases") { Task { await cloud.restore() } }
                    .disabled(cloud.isPurchasing)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// One request (right) or answer (left) of the conversation.
private struct Bubble: View {
    let entry: AssistantModel.Entry

    var body: some View {
        let request = entry.kind == .request
        Text(verbatim: entry.text)
            .foregroundStyle(entry.kind == .failure ? TVTheme.warning : TVTheme.text)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(request ? TVTheme.accent.opacity(0.55) : Color.white.opacity(0.08), in: .rect(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: request ? .trailing : .leading)
            .textSelection(.enabled)
            .accessibilityIdentifier(request ? "assistant.request" : "assistant.answer")
    }
}

/// What Fernsy Cloud includes, for the offers in Settings and the assistant (cloud-assistant design 9).
struct CloudOfferParts: View {
    var body: some View {
        ForEach(CloudModel.offerParts, id: \.self) { part in
            Label { Text(verbatim: part) } icon: { Image(systemName: "checkmark").foregroundStyle(TVTheme.accentLight) }
                .foregroundStyle(TVTheme.secondary)
        }
    }
}
