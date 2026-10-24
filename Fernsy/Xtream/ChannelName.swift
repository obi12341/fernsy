import Foundation

/// A provider's channel or category name split into what people read and what tells
/// duplicates apart: "|DE| RTL FHD" → name "RTL", country "DE", quality "FHD".
/// Names in which nothing is recognised stay exactly as delivered.
struct ChannelName: Hashable, Sendable {
    let raw: String
    let name: String
    let country: String?
    let quality: String?

    static func parse(_ raw: String) -> ChannelName {
        var text = trimDecoration(raw)
        var country: String?
        if let (code, rest) = countryPrefix(text) {
            country = code
            text = trimDecoration(rest)
        }
        var quality: String?
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while words.count > 1, let tag = qualityTag(words[words.count - 1]) {
            quality = tag  // the first marker after the name wins: "FHD HEVC" → FHD
            words.removeLast()
        }
        text = trimDecoration(words.joined(separator: " "))
        guard !text.isEmpty else { return ChannelName(raw: raw, name: raw, country: nil, quality: nil) }
        return ChannelName(raw: raw, name: text, country: country, quality: quality)
    }

    // MARK: Rules

    private static let decoration = Set("#=*★☆▎▍▌|~-_•·:".unicodeScalars)

    private static func trimDecoration(_ s: String) -> String {
        var scalars = Substring(s).unicodeScalars[...]
        while let first = scalars.first, decoration.contains(first) || CharacterSet.whitespaces.contains(first) { scalars = scalars.dropFirst() }
        while let last = scalars.last, decoration.contains(last) || CharacterSet.whitespaces.contains(last) { scalars = scalars.dropLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Codes that count as a country: ISO 3166 regions plus what IPTV lists commonly use.
    /// Words like "TV" or "HD" are not codes, so they never become tags.
    private static let codes: Set<String> = {
        var set = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 && $0.allSatisfy(\.isLetter) })
        set.formUnion(["UK", "EN", "EXYU", "ARAB", "LAT", "USA", "GER"])
        set.subtract(["TV"])  // Tuvalu: far more often "TV: Classics"
        return set
    }()

    /// "|DE| x", "[DE] x", "(DE) x", "DE: x", "DE - x", "DE | x", "DE ▎ x".
    private static let prefix = try! NSRegularExpression(
        pattern: #"^(?:[|\[(]\s*([A-Z]{2,4})\s*[|\])]|([A-Z]{2,4})\s*(?::|\s[-–|▎]|[|▎]))\s*(.+)$"#)

    private static func countryPrefix(_ s: String) -> (String, String)? {
        let ns = s as NSString
        guard let m = prefix.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let codeRange = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
        let code = ns.substring(with: codeRange)
        guard codes.contains(code) else { return nil }
        return (code, ns.substring(with: m.range(at: 3)))
    }

    private static let qualityPattern = try! NSRegularExpression(
        pattern: #"^(?:(SD|HD|FHD|UHD|4K|8K)(RAW)?|HEVC|H265|H\.265|50FPS|60FPS)$"#, options: [.caseInsensitive])

    private static func qualityTag(_ word: String) -> String? {
        let w = word.replacingOccurrences(of: "ᴴᴰ", with: "HD").trimmingCharacters(in: CharacterSet(charactersIn: "+"))
        let ns = w as NSString
        guard let m = qualityPattern.firstMatch(in: w, range: NSRange(location: 0, length: ns.length)) else { return nil }
        if m.range(at: 1).location != NSNotFound {
            let base = ns.substring(with: m.range(at: 1)).uppercased()
            return m.range(at: 2).location != NSNotFound ? base + " raw" : base
        }
        return w.uppercased()
    }

    #if DEBUG
    /// IPTV_NAMETEST=1: the spec's examples and known edge cases.
    static func selfTest() {
        let cases: [(String, String, String?, String?)] = [
            ("|DE| RTL FHD", "RTL", "DE", "FHD"),
            ("########## ADULT ##########", "ADULT", nil, nil),
            ("Kanal Süd", "Kanal Süd", nil, nil),
            ("TV: Classics", "TV: Classics", nil, nil),
            ("DE: ZDF", "ZDF", "DE", nil),
            ("[DE] ZDF", "ZDF", "DE", nil),
            ("DE - ZDF", "ZDF", "DE", nil),
            ("DE ▎ ZDF", "ZDF", "DE", nil),
            ("DE: ZDF HD", "ZDF", "DE", "HD"),
            ("DE: ZDF SD", "ZDF", "DE", "SD"),
            ("DE: Das Erste HD", "Das Erste", "DE", "HD"),
            ("UK: BBC One FHD", "BBC One", "UK", "FHD"),
            ("RT Doc", "RT Doc", nil, nil),
            ("ARD-alpha", "ARD-alpha", nil, nil),
            ("ZDF HDraw Cable", "ZDF HDraw Cable", nil, nil),
            ("Das Erste HDraw", "Das Erste", nil, "HD raw"),
            ("Northern Light 1 HD", "Northern Light 1", nil, "HD"),
            ("HD", "HD", nil, nil),
            ("4K", "4K", nil, nil),
            ("FR: TF1 FHD HEVC", "TF1", "FR", "FHD"),
        ]
        for (raw, name, country, quality) in cases {
            let p = parse(raw)
            let ok = p.name == name && p.country == country && p.quality == quality
            debugLog("[test] channel name \(ok ? "pass" : "FAIL"): \"\(raw)\" → \"\(p.name)\" \(p.country ?? "-") \(p.quality ?? "-")")
        }
    }
    #endif
}
