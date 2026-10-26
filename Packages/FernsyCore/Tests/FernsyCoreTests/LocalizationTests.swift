import Foundation
import Testing
@testable import FernsyCore

/// English is the source language, German a translation (localization spec).
struct LocalizationTests {
    /// The package's strings resolve from its own catalog, in both languages.
    @Test func packageStringsAreTranslated() throws {
        let english = String(localized: "Invalid server address", bundle: .fernsyCore, locale: Locale(identifier: "en"))
        #expect(english == "Invalid server address")
        let path = try #require(Bundle.fernsyCore.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path)).localizedString(forKey: "Invalid server address", value: nil, table: nil)
        #expect(german == "Ungültige Server-Adresse")
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let catalogs = [
        "Fernsy/Localizable.xcstrings", "Fernsy/AppShortcuts.xcstrings", "Fernsy/InfoPlist.xcstrings",
        "Packages/FernsyCore/Sources/FernsyCore/Resources/Localizable.xcstrings",
        "Packages/FernsyPlayer/Sources/FernsyPlayer/Resources/Localizable.xcstrings",
    ]

    /// Every key has a German translation, so no string ships English-only in the German UI.
    @Test(arguments: catalogs)
    func everyKeyHasGerman(_ catalog: String) throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(catalog))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["sourceLanguage"] as? String == "en")
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        #expect(!strings.isEmpty)
        for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as? [String: Any]
            guard key.contains(where: \.isLetter) else { continue }  // "%lld", "–" and the like
            #expect(localizations?["de"] != nil, "no German for \"\(key)\" in \(catalog)")
        }
    }
}
