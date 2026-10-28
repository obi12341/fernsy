import SwiftUI

/// A horizontal row that can also be paged with buttons, so a mouse without a horizontal scroll
/// wheel reaches every card (Jellyfin's rows, Start and Übersicht; mac-start-pages design 3).
struct PagingCarousel<Item: Identifiable, Card: View>: View where Item.ID: Hashable {
    let title: Text
    /// A quieter word after the title ("Favorites", "Jellyfin").
    var note: Text?
    let items: [Item]
    let itemWidth: CGFloat
    /// Fixed row height: lazy rows otherwise size to the first cards and clip taller ones.
    let height: CGFloat
    @ViewBuilder let card: (Item) -> Card

    @State private var position: Item.ID?
    @State private var visibleCount = 4
    private let spacing: CGFloat = 18

    var body: some View {
        let index = position.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                title.font(.title2.weight(.semibold))
                if let note { note.font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button { page(from: index, by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                    .help("Back")
                Button { page(from: index, by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(index + visibleCount >= items.count)
                    .help("Next")
            }
            .buttonStyle(.borderless)
            .font(.title3)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        card(item).frame(width: itemWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: height)
            .scrollPosition(id: $position, anchor: .leading)
            .scrollTargetBehavior(.viewAligned)
            .onGeometryChange(for: Int.self) { geo in
                max(1, Int((geo.size.width + spacing) / (itemWidth + spacing)))
            } action: { visibleCount = $0 }
        }
    }

    private func page(from index: Int, by direction: Int) {
        let target = min(max(0, index + direction * visibleCount), max(0, items.count - visibleCount))
        withAnimation(.snappy) { position = items[target].id }
    }
}
