import SwiftUI

/// A small outlined tag next to a channel or category name ("DE", "FHD").
struct NameTag: View {
    let text: String
    var prominent = true

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(prominent ? .secondary : .tertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.tagBorder, lineWidth: 1))
            .fixedSize()
    }
}

/// The cleaned name followed by its country and quality tags.
struct TaggedName: View {
    let name: ChannelName
    var font: Font = .body
    var weight: Font.Weight = .regular

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: name.name)
                .font(font)
                .fontWeight(weight)
                .lineLimit(1)
            if let country = name.country { NameTag(text: country) }
            if let quality = name.quality { NameTag(text: quality, prominent: false) }
        }
    }
}
