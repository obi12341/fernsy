import Foundation

/// What every subscription offer shows besides the benefits (subscription-terms-links, App Store
/// guideline 3.1.2): length, renewal, and links to the Terms of Use and the privacy policy.
/// App Store builds link Apple's standard EULA; the DMG sells through Stripe and links the terms
/// on fernsy.app.
public struct CloudTerms: Equatable, Sendable {
    /// The DMG's website purchase (`WebCloudStore`) instead of StoreKit.
    public var web: Bool
    /// Which of the website's pages to link: "de" for the German ones, anything else for English.
    /// The texts follow the app's language like every FernsyCore string.
    public var language: String

    public init(web: Bool, language: String = Bundle.main.preferredLocalizations.first ?? "en") {
        self.web = web
        self.language = language
    }

    private var german: Bool { language == "de" }

    /// The subscription's length, for "Fernsy Cloud · 1 month · 3,49 €".
    public var period: String { String(localized: "1 month", bundle: .module) }

    public var renewal: String {
        web
            ? String(localized: "Renews monthly until canceled. Cancel in Fernsy under Manage Subscription or by e-mail to info@mobilistics.de.", bundle: .module)
            : String(localized: "Renews monthly until canceled. Cancel at least 24 hours before the end of the period in your Apple account settings.", bundle: .module)
    }

    public var termsTitle: String { String(localized: "Terms of Use (EULA)", bundle: .module) }
    public var privacyTitle: String { String(localized: "Privacy Policy", bundle: .module) }

    public var termsURL: URL {
        if web { return URL(string: german ? "https://www.fernsy.app/agb.html" : "https://www.fernsy.app/en/terms.html")! }
        return URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    public var privacyURL: URL {
        URL(string: german ? "https://www.fernsy.app/datenschutz.html" : "https://www.fernsy.app/en/privacy.html")!
    }

    /// Name, length and price in one line; without a price while StoreKit has not answered.
    public func offerLine(_ offer: CloudModel.Offer?) -> String {
        guard let offer else { return "Fernsy Cloud · \(period)" }
        return "\(offer.name) · \(period) · \(offer.price)"
    }
}

extension CloudModel {
    /// The terms for this app's way of buying.
    public var terms: CloudTerms { CloudTerms(web: isWebStore) }
}
