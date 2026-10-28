import FernsyCore
import FernsyPlayer
import SwiftUI

/// The player's state in the middle of the screen (tvos-player-status), for the live and the
/// on-demand player: loading, buffering, reconnecting, why a live channel stalls, and a failure
/// with "Try Again" and "Next Channel". The cases follow the Mac's `statusOverlay`, so both
/// apps say the same thing at the same moment.
struct PlayerStatusLayer: View {
    @EnvironmentObject private var model: TVModel
    @ObservedObject var engine: PlayerEngine
    let title: String
    /// The live channel, for its logo; nil for films, episodes and recordings.
    var channel: LiveChannel?
    /// An item is chosen but the engine has not started it yet (a Jellyfin item resolving its
    /// stream): shown as loading (design 2).
    var pending = false
    /// The failure card may take focus: no other overlay (strip, tracks) is open (design 5).
    var canTakeFocus = true
    let retry: () -> Void
    var next: (() -> Void)?
    let close: () -> Void

    /// Cards stay dark over any picture (a material turns light over a bright one).
    static let plate = Color(hex: 0x16151B, opacity: 0.88)

    /// Live playback has been buffering for a second (short stalls stay a plain spinner).
    @State private var stallVisible = false
    @FocusState private var focus: Action?

    enum Action: Hashable { case retry, next }

    enum Kind: Equatable {
        case none, loading, spinner, reconnecting, stall, offline, failed(String)

        var marker: String {
            switch self {
            case .none: "none"
            case .loading: "loading"
            case .spinner: "spinner"
            case .reconnecting: "reconnecting"
            case .stall: "stall"
            case .offline: "offline"
            case .failed: "failed"
            }
        }
    }

    var body: some View {
        let kind = self.kind
        ZStack {
            switch kind {
            case .none:
                EmptyView()
            case .loading:
                // The last picture of the previous item stays behind; dimmed, it reads as waiting.
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 28) {
                    if let channel {
                        ChannelLogo(channel: channel, radius: 20, logoPadding: 16).frame(width: 220, height: 132)
                    }
                    ProgressView().scaleEffect(1.6).tint(.white)
                    Text("Loading \(title)…").font(.system(size: 30, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
            case .spinner:
                ProgressView().scaleEffect(1.6).tint(.white)
            case .reconnecting:
                card {
                    ProgressView().tint(.white)
                    Text("Reconnecting…").font(.system(size: 32, weight: .semibold))
                    if engine.reconnectAttempt > 0 {
                        Text("Attempt \(engine.reconnectAttempt) of \(PlayerEngine.maxReconnectAttempts)")
                            .font(.system(size: 24)).foregroundStyle(.white.opacity(0.65))
                    }
                }
            case .stall:
                if let cause = stallCause {
                    card {
                        Image(systemName: cause.symbol).font(.system(size: 40, weight: .semibold))
                        Text(cause.title).font(.system(size: 32, weight: .semibold))
                        HStack(spacing: 14) {
                            ProgressView().tint(.white)
                            Text(cause.detail)
                        }
                        .font(.system(size: 24)).foregroundStyle(.white.opacity(0.7))
                    }
                }
            case .offline, .failed:
                failure(kind)
            }
            if engine.showsServerSwitchNote {
                Label("Another server of the provider delivers smoothly again.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(Self.plate, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("player.status")
                .accessibilityValue(kind.marker)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.25), value: engine.showsServerSwitchNote)
        .task(id: engine.status == .buffering && channel != nil) {
            stallVisible = false
            guard engine.status == .buffering, channel != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { stallVisible = true }
        }
        // The failure card's first button takes focus, unless another overlay is open.
        .onChange(of: isFailure && canTakeFocus, initial: true) { _, take in
            if take { focus = .retry }
        }
    }

    private var isFailure: Bool { if case .failed = engine.status { true } else { false } }

    /// What shows, in the Mac's order: loading, reconnecting, the stall's cause, the spinner,
    /// the failure.
    var kind: Kind {
        switch engine.status {
        case .idle:
            return pending ? .loading : .none
        case .loading where !engine.isReconnecting:
            return .loading
        case .loading, .buffering:
            if engine.isReconnecting || engine.reconnectAttempt > 0 { return .reconnecting }
            if stallVisible, stallCause != nil { return .stall }
            return .spinner
        case .failed(let message):
            return message == PlayerError.offline.localizedDescription ? .offline : .failed(message)
        case .playing, .paused, .ended:
            return .none
        }
    }

    /// Why live playback stalls, when Fernsy has evidence for it: no network, or the channel's
    /// connection delivers too slowly, nothing, or is being replaced. Nil while it is healthy.
    private var stallCause: (symbol: String, title: String, detail: String)? {
        guard channel != nil else { return nil }
        if !model.isNetworkAvailable {
            return ("wifi.slash", String(localized: "No internet connection"),
                    String(localized: "Fernsy continues as soon as the network is back."))
        }
        switch engine.connectionHealth {
        case .ok:
            return nil
        case .reconnecting(loadBalancer: true):
            return ("tortoise", String(localized: "The channel arrives too slowly from the provider"),
                    String(localized: "Fernsy is switching to another server of the provider …"))
        case .slow, .silent, .reconnecting:
            return ("tortoise", String(localized: "The channel arrives too slowly from the provider"),
                    String(localized: "Fernsy is waiting for data …"))
        }
    }

    private func failure(_ kind: Kind) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Color(hex: 0x1A1300))
                .frame(width: 64, height: 64)
                .background(TVTheme.warning, in: Circle())
            if case .failed(let message) = kind {
                Text(verbatim: message).font(.system(size: 32, weight: .semibold)).multilineTextAlignment(.center)
            } else {
                Text("Channel is offline at the provider").font(.system(size: 32, weight: .semibold))
                Text("\(title) is not sending a picture right now. This is the provider, not your connection.")
                    .font(.system(size: 24)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            }
            HStack(spacing: 24) {
                Button(action: retry) { Text("Try Again") }
                    .buttonStyle(ActionButtonStyle())
                    .focused($focus, equals: .retry)
                    .accessibilityIdentifier("player.status.retry")
                if let next {
                    Button(action: next) { Text("Next Channel") }
                        .buttonStyle(ActionButtonStyle())
                        .focused($focus, equals: .next)
                        .accessibilityIdentifier("player.status.next")
                }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, 56).padding(.vertical, 44)
        .background(Self.plate, in: .rect(cornerRadius: 32))
        .focusSection()
        .onExitCommand(perform: close)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 16, content: content)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 820)
            .padding(.horizontal, 48).padding(.vertical, 32)
            .background(Self.plate, in: .rect(cornerRadius: 28))
            .allowsHitTesting(false)
    }
}
