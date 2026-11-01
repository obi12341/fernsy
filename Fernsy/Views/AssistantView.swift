import FernsyCore
import SwiftUI

/// Window › Assistant (cloud-assistant): the session's conversation and a text field (system
/// dictation works in it), a spinner while waiting. Actions run at once, cancelling a recording
/// asks first. Without a subscription it offers Fernsy Cloud, before the first request it asks
/// for consent.
struct AssistantView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let assistant = app.assistant
        Group {
            if !assistant.isAvailable {
                AssistantOffer()
            } else if !assistant.hasConsent {
                consent(assistant)
            } else {
                AssistantConversation(assistant: assistant)
            }
        }
        .frame(minWidth: 400, minHeight: 420)
        .toolbar {
            if assistant.hasConsent && assistant.isAvailable {
                ToolbarItem {
                    Button("New Conversation", systemImage: "square.and.pencil") { assistant.reset() }
                        .help("Start a new conversation")
                        .disabled(assistant.isWaiting || assistant.entries.isEmpty)
                }
            }
        }
        .alert(assistant.question ?? "", isPresented: Binding(get: { assistant.question != nil },
                                                             set: { if !$0 { assistant.answerQuestion(false) } })) {
            Button("Remove", role: .destructive) { assistant.answerQuestion(true) }
            Button("Keep", role: .cancel) { assistant.answerQuestion(false) }
        }
        // Closed while a tool asks: nothing is removed.
        .onDisappear { if assistant.question != nil { assistant.answerQuestion(false) } }
    }

    private func consent(_ assistant: AssistantModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Before the first request", systemImage: "hand.raised").font(.title3.bold())
            Text(verbatim: AssistantModel.consentText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Not Now") { dismissWindow(id: "assistant") }
                Button("Agree") { assistant.agree() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("assistant.consent.agree")
            }
            Spacer()
        }
        .padding(24)
    }
}

private struct AssistantConversation: View {
    let assistant: AssistantModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if assistant.entries.isEmpty {
                            Text("Ask for a channel, a show, a movie or a recording – typed or dictated.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(assistant.entries) { entry in
                            Bubble(entry: entry).id(entry.id)
                        }
                        if assistant.isWaiting {
                            ProgressView().controlSize(.small).accessibilityIdentifier("assistant.waiting")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: assistant.entries.count) {
                    withAnimation { proxy.scrollTo(assistant.entries.last?.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask Fernsy", text: Binding(get: { assistant.draft }, set: { assistant.draft = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { Task { await assistant.send() } }
                    .accessibilityIdentifier("assistant.field")
                Button("Ask") { Task { await assistant.send() } }
                    .disabled(assistant.isWaiting || assistant.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("assistant.send")
            }
            .padding(12)
        }
        .onAppear { fieldFocused = true }
    }
}

/// One request (right) or answer (left) of the conversation.
private struct Bubble: View {
    let entry: AssistantModel.Entry

    var body: some View {
        let request = entry.kind == .request
        Text(verbatim: entry.text)
            .foregroundStyle(entry.kind == .failure ? Theme.warning : .primary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(request ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07), in: .rect(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: request ? .trailing : .leading)
            .textSelection(.enabled)
            .accessibilityIdentifier(request ? "assistant.request" : "assistant.answer")
    }
}

/// Without a subscription: what Fernsy Cloud includes, buy or restore.
private struct AssistantOffer: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let cloud = app.cloud
        VStack(alignment: .leading, spacing: 16) {
            Label("Fernsy Cloud", systemImage: "icloud").font(.title2.bold())
            Text("The assistant is part of Fernsy Cloud.").font(.headline)
            CloudOfferParts()
            if let offer = cloud.offer {
                Text("\(offer.name) – \(offer.price) per month")
            }
            HStack {
                Button("Subscribe") { Task { await cloud.purchase() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(cloud.isPurchasing)
                    .accessibilityIdentifier("assistant.subscribe")
                Button("Restore Purchases") { Task { await cloud.restore() } }
                    .disabled(cloud.isPurchasing)
                if cloud.isPurchasing { ProgressView().controlSize(.small) }
            }
            if case .failed(let message) = cloud.phase {
                Text(verbatim: message).foregroundStyle(Theme.warning)
            }
            Spacer()
        }
        .padding(24)
        .task { await cloud.refreshSubscription() }
    }
}

/// What Fernsy Cloud includes, for its offers (cloud-assistant design 9).
struct CloudOfferParts: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(CloudModel.offerParts, id: \.self) { part in
                Label { Text(verbatim: part).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}

/// Window › Assistant… (⌘K), with Fernsy Cloud only.
struct AssistantCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            if CloudFeature.isEnabled {
                Button("Assistant…") { openWindow(id: "assistant") }
                    .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}
