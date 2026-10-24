import SwiftUI

/// The redesign's status marks: always symbol or text together with colour, never colour
/// alone. Red is reserved for recording and live.
struct StatusBadge: View {
    enum Kind {
        case playing, recording, scheduled, favorite, offline, hidden, live
        /// Time behind live, e.g. "−12:34".
        case behind(String)
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case .playing:
            Label("Im Player", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .labelStyle(.titleAndIcon)
        case .recording:
            HStack(spacing: 4) {
                Circle().fill(Theme.record).frame(width: 7, height: 7)
                Text("REC").font(.caption2.weight(.bold)).tracking(0.4)
            }
            .foregroundStyle(Theme.record)
        case .scheduled:
            HStack(spacing: 4) {
                Circle().strokeBorder(Theme.record, lineWidth: 1.5).frame(width: 8, height: 8)
                Text("Geplant").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Theme.record)
        case .favorite:
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
                .accessibilityLabel("Favorit")
                .help("Favorit")
        case .offline:
            pill("Offline")
        case .hidden:
            pill("Ausgeblendet")
        case .live:
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("LIVE").font(.caption2.weight(.heavy)).tracking(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Theme.record, in: Capsule())
        case .behind(let text):
            Text(text)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }

    private func pill(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}
