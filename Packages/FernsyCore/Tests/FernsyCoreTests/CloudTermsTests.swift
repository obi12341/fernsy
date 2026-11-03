import Foundation
import Testing
@testable import FernsyCore

/// What every subscription offer shows (subscription-terms-links).
struct CloudTermsTests {
    @Test func appStoreBuildsLinkApplesStandardEULA() {
        let terms = CloudTerms(web: false, language: "de")
        #expect(terms.termsURL.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        #expect(terms.privacyURL.absoluteString == "https://www.fernsy.app/datenschutz.html")
        #expect(CloudTerms(web: false, language: "en").privacyURL.absoluteString == "https://www.fernsy.app/en/privacy.html")
    }

    @Test func theDMGLinksTheWebsiteTerms() {
        #expect(CloudTerms(web: true, language: "de").termsURL.absoluteString == "https://www.fernsy.app/agb.html")
        #expect(CloudTerms(web: true, language: "en").termsURL.absoluteString == "https://www.fernsy.app/en/terms.html")
    }

    @Test func theOfferLineNamesLengthAndPrice() {
        let terms = CloudTerms(web: false, language: "en")
        #expect(terms.offerLine(CloudModel.Offer(name: "Fernsy Cloud", price: "€3.49")).hasPrefix("Fernsy Cloud · "))
        #expect(terms.offerLine(CloudModel.Offer(name: "Fernsy Cloud", price: "€3.49")).hasSuffix(" · €3.49"))
        // Before StoreKit answered: name and length, Apple's sheet shows the price.
        #expect(!terms.offerLine(nil).contains("€"))
    }

    @Test(arguments: [
        ("1 month", "1 Monat"),
        ("Terms of Use (EULA)", "Nutzungsbedingungen (EULA)"),
        ("Privacy Policy", "Datenschutzerklärung"),
        ("Renews monthly until canceled. Cancel at least 24 hours before the end of the period in your Apple account settings.",
         "Verlängert sich monatlich, bis du kündigst. Kündige spätestens 24 Stunden vor Ablauf des Zeitraums in den Einstellungen deines Apple Accounts."),
    ])
    func theTextsAreTranslated(_ key: String, _ german: String) throws {
        let path = try #require(Bundle.fernsyCore.path(forResource: "de", ofType: "lproj"))
        #expect(try #require(Bundle(path: path)).localizedString(forKey: key, value: nil, table: nil) == german)
    }
}
