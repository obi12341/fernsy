import FernsyCore
import FernsyPlayer
import SwiftUI

/// TV-style channel banner: number, logo, name, what is on now and what follows.
struct ChannelOSD: View {
    @EnvironmentObject private var app: AppModel
    let channel: LiveChannel
    let number: Int
    /// Still choosing (key presses continue); the channel is not tuned yet.
    let isPending: Bool
    @State private var now: EPGEntry?
    @State private var next: EPGEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text(verbatim: "\(number)")
                    .font(.system(size: 26, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(minWidth: 50, alignment: .leading)
                LogoTile(url: channel.icon, name: channel.displayName, width: 66)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        TaggedName(name: channel.parsed, font: .title3, weight: .bold)
                        if isPending {
                            ProgressView().controlSize(.small).tint(.white).opacity(0.7)
                        }
                    }
                    if let now {
                        Text(verbatim: "\(now.title) · \(now.start.formatted(date: .omitted, time: .shortened))–\(now.end.formatted(date: .omitted, time: .shortened))")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            if let now {
                ProgressBar(value: now.progress, tint: .white, height: 4)
            }
            HStack {
                if let next {
                    Text("Next \(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)")
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    keyCap("↑")
                    keyCap("↓")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 440, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 25, y: 18)
        .environment(\.colorScheme, .dark)
        .task(id: channel.id) {
            now = nil
            next = nil
            // Short debounce: no EPG request for channels that are only skipped past.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let entries = (try? await app.client?.shortEPG(channel.id, limit: 3)) ?? []
            now = entries.first { $0.start <= Date() && $0.end > Date() } ?? entries.first
            next = entries.first { $0.start >= (now?.end ?? Date()) }
        }
    }

    private func keyCap(_ key: String) -> some View {
        Text(verbatim: key)
            .padding(.horizontal, 5)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
    }
}
