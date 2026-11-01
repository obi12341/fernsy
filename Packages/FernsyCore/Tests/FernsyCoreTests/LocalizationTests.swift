import Foundation
import Testing
@testable import FernsyCore
@testable import FernsyShared

/// English is the source language, German a translation (localization spec).
struct LocalizationTests {
    /// The package's strings resolve from its own catalogs, in both languages.
    @Test(arguments: [
        (Bundle.fernsyCore, "Buffer", "Puffer"),
        (Bundle.fernsyShared, "Invalid server address", "Ungültige Server-Adresse"),
    ])
    func packageStringsAreTranslated(_ bundle: Bundle, _ key: String, _ translation: String) throws {
        let english = String(localized: String.LocalizationValue(key), bundle: bundle, locale: Locale(identifier: "en"))
        #expect(english == key)
        let path = try #require(bundle.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path)).localizedString(forKey: key, value: nil, table: nil)
        #expect(german == translation)
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let catalogs = [
        "Fernsy/Localizable.xcstrings", "Fernsy/AppShortcuts.xcstrings", "Fernsy/InfoPlist.xcstrings",
        "Packages/FernsyCore/Sources/FernsyCore/Resources/Localizable.xcstrings",
        "Packages/FernsyCore/Sources/FernsyShared/Resources/Localizable.xcstrings",
        "Packages/FernsyPlayer/Sources/FernsyPlayer/Resources/Localizable.xcstrings",
        "FernsyTV/Localizable.xcstrings",
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

    /// British forms that must not appear in English source texts (us-english-strings).
    static let british = [#"\bfilms?\b"#, "favourit", "programme", "colour", "centre", "catalogue", "behaviour", "cancelled", "licence"]

    /// The English source texts use US spelling and wording ("Movies", "Favorites", "program").
    @Test(arguments: catalogs)
    func englishIsUSEnglish(_ catalog: String) throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(catalog))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        for key in strings.keys {
            for pattern in Self.british where key.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                Issue.record("British \"\(pattern)\" in \"\(key)\" (\(catalog))")
            }
        }
    }
}
