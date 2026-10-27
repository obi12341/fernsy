import FernsyCore
import SwiftUI

/// All live categories (design screen `kategorien`): a grid with country filters and a search
/// over the names. Click opens the category in Live TV; a long press pins or hides it.
struct AllCategoriesScreen: View {
    @EnvironmentObject private var model: TVModel
    let open: (XCategory) -> Void
    @State private var filter: Filter = .all
    @State private var query = ""

    enum Filter: Hashable {
        case all, pinned, noCountry
        case country(String)
    }

    private var categories: [XCategory] { model.visibleCategories }

    private var shown: [XCategory] {
        categories.filter { category in
            let matches: Bool = switch filter {
            case .all: true
            case .pinned: model.isPinned(category)
            case .noCountry: category.parsed.country == nil
            case .country(let code): category.parsed.country == code
            }
            return matches && (query.isEmpty || category.displayName.localizedStandardContains(query))
        }
    }

    /// The countries found in the category names, most categories first.
    private var countries: [(code: String, count: Int)] {
        Dictionary(grouping: categories.compactMap(\.parsed.country)) { $0 }
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 24) {
                Text("All Categories").font(.system(size: 52, weight: .bold))
                Text(verbatim: "\(categories.count)").font(.system(size: 24)).foregroundStyle(TVTheme.text.opacity(0.55))
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search categories", text: $query)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("categories.search")
                }
                .font(.system(size: 23))
                .padding(.horizontal, 24)
                .frame(width: 420, height: 60)
                .background(Color.white.opacity(0.1), in: .capsule)
            }
            .padding(.top, 70)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    chip(Text("All"), id: "all", .all, count: categories.count)
                    chip(Text("Pinned"), id: "pinned", .pinned, count: categories.filter(model.isPinned).count)
                    ForEach(countries, id: \.code) { chip(Text(verbatim: $0.code), id: $0.code, .country($0.code), count: $0.count) }
                    let none = categories.filter { $0.parsed.country == nil }.count
                    if none > 0 { chip(Text("No Country"), id: "none", .noCountry, count: none) }
                }
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            .focusSection()
            .padding(.top, 16)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 5), spacing: 24) {
                    ForEach(shown) { category in
                        Button { open(category) } label: { CategoryTile(category: category) }
                            .buttonStyle(TVTileStyle(radius: 18, scale: 1.05))
                            .contextMenu {
                                Button(model.isPinned(category) ? "Unpin" : "Pin", systemImage: model.isPinned(category) ? "pin.slash" : "pin") {
                                    model.setPinned(category, !model.isPinned(category))
                                }
                                Button("Hide", systemImage: "eye.slash") { model.setHidden(category, true) }
                            }
                            .accessibilityIdentifier("category.\(category.id)")
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
            .focusSection()

            HStack(spacing: 34) {
                Text("Click: Open Category")
                Text("Hold: Pin, Hide")
                Text("Back: Live TV")
            }
            .font(.system(size: 20))
            .foregroundStyle(TVTheme.text.opacity(0.55))
            .padding(.bottom, 44)
        }
        .padding(.horizontal, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x16151B).ignoresSafeArea())
        .foregroundStyle(TVTheme.text)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private func chip(_ title: Text, id: String, _ value: Filter, count: Int) -> some View {
        Button { filter = value } label: {
            HStack(spacing: 10) {
                title
                Text(verbatim: "\(count)").font(.system(size: 18)).opacity(0.6)
            }
            .font(.system(size: 22, weight: .semibold))
            .padding(.horizontal, 24)
            .frame(height: 52)
        }
        .buttonStyle(ChipStyle(selected: filter == value))
        .accessibilityIdentifier("categories.chip.\(id)")
    }
}

private struct CategoryTile: View {
    @EnvironmentObject private var model: TVModel
    let category: XCategory
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(verbatim: category.displayName).font(.system(size: 25, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if model.isPinned(category) {
                    Image(systemName: "pin.fill").font(.system(size: 18)).foregroundStyle(Color(hex: 0xFF6B5E))
                }
            }
            HStack(spacing: 10) {
                if let country = category.parsed.country { CountryTag(text: country) }
                Text("\(model.channels(for: .category(category.id)).count) channels").opacity(0.6)
            }
            .font(.system(size: 19))
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
    }
}

private struct ChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, selected: selected)
    }

    private struct Chip: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? TVTheme.focusedText : selected ? TVTheme.text : TVTheme.text.opacity(0.72))
                .background(focused ? TVTheme.focused : selected ? Color.white.opacity(0.22) : Color.white.opacity(0.08), in: .capsule)
                .scaleEffect(focused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
