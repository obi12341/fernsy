import FernsyCore
import FernsyPlayer
import SwiftUI

/// A page the library screens open: a film or series of either source.
enum DetailTarget: Hashable {
    case movie(Movie)
    case series(Series)
    case jellyfin(JFItem)

    static func of(_ target: LibraryEntry.Target) -> DetailTarget? {
        switch target {
        case .movie(let movie): .movie(movie)
        case .series(let series), .episode(_, let series): .series(series)
        case .jellyfin(let item): item.type == "Episode" ? nil : .jellyfin(item)
        case .recording: nil
        }
    }
}

/// The page for a target: film page or series page.
struct DetailScreen: View {
    let target: DetailTarget

    var body: some View {
        switch target {
        case .movie(let movie): FilmScreen(film: .iptv(movie))
        case .series(let series): SeriesScreen(show: .iptv(series))
        case .jellyfin(let item): item.type == "Series" ? AnyView(SeriesScreen(show: .jellyfin(item))) : AnyView(FilmScreen(film: .jellyfin(item)))
        }
    }
}

/// A poster (200×300 in the design) with its title, a rating and the "Neu" mark.
struct PosterCard: View {
    let title: String
    let image: URL?
    var rating: Double?
    var isNew = false
    var badge: String?
    var badgeColor: Color = Color(hex: 0x0F0E12, opacity: 0.62)
    var count: Int?
    var progress: Double?
    var watched = false
    var width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RemoteImage(url: image, maxPixel: Int(width * 2)) { ArtPlaceholder(seed: title) }
                    .frame(width: width, height: width * 1.5)
                    .clipped()
                if isNew { Tag(text: Text("New"), background: Color(hex: 0x6C65F0)).padding(10) }
                if let badge { Tag(text: Text(verbatim: badge), background: badgeColor).padding(10) }
                if let count, count > 0 {
                    Text(verbatim: "\(count)").font(.system(size: 17, weight: .bold))
                        .frame(minWidth: 34, minHeight: 34).background(Color(hex: 0x6C65F0), in: .circle)
                        .frame(maxWidth: .infinity, alignment: .topTrailing).padding(10)
                }
                if watched {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy))
                        .frame(width: 34, height: 34).background(Color(hex: 0x6C65F0), in: .circle)
                        .frame(maxWidth: .infinity, alignment: .topTrailing).padding(10)
                }
                VStack {
                    Spacer()
                    HStack {
                        if let rating, rating > 0 {
                            Tag(text: Text("★ \(rating.formatted(.number.precision(.fractionLength(1))))"),
                                background: Color(hex: 0x0F0E12, opacity: 0.62))
                        }
                        Spacer()
                    }
                    if let progress { ProgressBar(value: progress) }
                }
                .padding(10)
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(.rect(cornerRadius: 14))
            Text(verbatim: title).font(.system(size: 21, weight: .semibold)).lineLimit(1).frame(width: width, alignment: .leading)
        }
    }
}

/// A wide card (400×225): source tag, progress, title and a detail line under it.
struct WideCard: View {
    let title: String
    let detail: String
    let image: URL?
    var source: String?
    var progress: Double?
    var topRight: AnyView?
    var topLeft: AnyView?
    var width: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                RemoteImage(url: image, maxPixel: Int(width * 2)) { ArtPlaceholder(seed: title) }
                    .frame(width: width, height: width * 9 / 16)
                    .clipped()
                if let source { Tag(text: Text(verbatim: source), background: Color(hex: 0x0F0E12, opacity: 0.6)).padding(14) }
                if let topLeft { topLeft.padding(14) }
                if let topRight { topRight.frame(maxWidth: .infinity, alignment: .topTrailing).padding(14) }
                if let progress { ProgressBar(value: progress).padding(16).frame(maxHeight: .infinity, alignment: .bottom) }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(.rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                Text(verbatim: detail).font(.system(size: 20)).foregroundStyle(TVTheme.text.opacity(0.6)).lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

struct Tag: View {
    let text: Text
    let background: Color
    var foreground: Color = .white

    var body: some View {
        text.font(.system(size: 16, weight: .bold))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(background, in: .rect(cornerRadius: 8))
            .foregroundStyle(foreground)
    }
}

struct ProgressBar: View {
    let value: Double
    var fill: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(fill).frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 6)
    }
}

/// A row title with an optional note ("Zuletzt hinzugefügt · IPTV und Jellyfin").
struct RowTitle: View {
    let title: LocalizedStringKey
    var note: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.system(size: 30, weight: .bold))
            if let note { Text(note).font(.system(size: 21)).foregroundStyle(TVTheme.text.opacity(0.55)) }
        }
    }
}

/// A horizontal row of cards that keeps the focused card's scale visible.
struct CardRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 40) { content }
                .padding(.vertical, 24)
                .padding(.horizontal, 4)
        }
        .scrollClipDisabled()
    }
}

/// The design's round icon buttons and wide action buttons on detail pages.
struct ActionButtonStyle: ButtonStyle {
    var round = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, round: round)
    }

    private struct Pill: View {
        let configuration: Configuration
        let round: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 29, weight: .semibold))
                .padding(.horizontal, round ? 0 : 40)
                .frame(minWidth: 84, minHeight: 84)
                .foregroundStyle(focused ? TVTheme.focusedText : TVTheme.text)
                .background(focused ? Color.white : Color.white.opacity(0.16), in: .capsule)
                .scaleEffect(focused ? 1.06 : 1)
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 20, y: 20)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Minutes as the design writes them: "2 Std. 4 Min.", "48 Min.".
enum Runtime {
    static func text(seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? String(localized: "\(minutes / 60) hr \(minutes % 60) min") : String(localized: "\(minutes) min")
    }
}
