import Testing
@testable import FernsyCore

/// The spec's examples and known edge cases (channel-names spec).
struct ChannelNameTests {
    static let cases: [(String, String, String?, String?)] = [
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

    @Test(arguments: cases)
    func parse(_ raw: String, _ name: String, _ country: String?, _ quality: String?) {
        let parsed = ChannelName.parse(raw)
        #expect(parsed.name == name, "\(raw)")
        #expect(parsed.country == country, "\(raw)")
        #expect(parsed.quality == quality, "\(raw)")
        #expect(parsed.raw == raw)
    }
}
