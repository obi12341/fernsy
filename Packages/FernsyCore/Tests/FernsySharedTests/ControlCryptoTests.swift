#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Testing
@testable import FernsyShared

/// Fernsy Control's keys (headless-recorder design 3, 4). The fixed values were computed with
/// Python's hmac/hashlib, so the derivations stay the same on every platform.
struct ControlCryptoTests {
    static let key = ControlKey(raw: Data(1...32))

    @Test func derivationsAreFixed() {
        #expect(Self.key.spaceId == "753d7acad526432123972c34d8b64c6d")
        #expect(Self.key.writeSecret.base64URL == "Kxs0cE4rEtIpu4J7Ui4TjoFujEgmVcPlNF1-zXVLclQ")
        #expect(Self.key.authorization == "Space 753d7acad526432123972c34d8b64c6d:Kxs0cE4rEtIpu4J7Ui4TjoFujEgmVcPlNF1-zXVLclQ")
    }

    @Test func itemsOpenOnlyUnderTheirKindAndId() throws {
        let sealed = try Self.key.seal(Data("20:15 Tagesschau".utf8), kind: "order", id: "o1")
        #expect(try Self.key.open(sealed, kind: "order", id: "o1") == Data("20:15 Tagesschau".utf8))
        #expect(throws: (any Error).self) { try Self.key.open(sealed, kind: "state", id: "o1") }
        #expect(throws: (any Error).self) { try ControlKey().open(sealed, kind: "order", id: "o1") }
    }

    @Test func pbkdf2MatchesTheReference() throws {
        // RFC 7914 section 11: PBKDF2-HMAC-SHA256, "passwd", "salt", 1 round.
        let key = try pbkdf2SHA256(password: Data("passwd".utf8), salt: Data("salt".utf8), rounds: 1, count: 32)
        #expect(key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
                == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc")
        let code = try #require(PairingCode("7K3Q-ABCDEF"))
        #expect(try code.key(rounds: 1000).withUnsafeBytes { Data($0) }.base64EncodedString()
                == "9AT90P8ywn5Wi5dgzjYI0lnwYhIywW5qt1tBLEg4SFs=")
    }

    @Test func pairingCodesReadWhatPeopleType() throws {
        let code = try #require(PairingCode("7k3q abcdef"))
        #expect(code.value == "7K3QABCDEF")
        #expect(code.display == "7K3Q-ABCDEF")
        #expect(code.mailbox == "7K3Q")
        #expect(PairingCode("OIL0-000000")?.value == "0110000000")
        #expect(PairingCode("7K3Q-ABCDE") == nil)
        #expect(PairingCode("7K3Q-ABCDEU") == nil)
        let made = PairingCode()
        #expect(PairingCode(made.display) == made)
    }

    @Test func secretsReachOnlyTheServerWithTheCode() throws {
        let server = Curve25519.KeyAgreement.PrivateKey()
        let code = PairingCode()
        let codeKey = try code.key(rounds: 1000)
        let secrets = PairingSecrets(controlKey: ControlKey(), cloudKey: CloudAccountKey(),
                                     login: XtreamCredentials(server: "https://example.com", username: "u", password: "p"))
        let (message, tag) = try secrets.seal(to: server.publicKey, codeKey: codeKey)
        #expect(try PairingSecrets.open(message, tag: tag, privateKey: server, codeKey: codeKey) == secrets)
        // Another code's key or another server cannot open it.
        #expect(throws: PairingSecrets.Failure.self) {
            try PairingSecrets.open(message, tag: tag, privateKey: server, codeKey: try PairingCode().key(rounds: 1000))
        }
        #expect(throws: (any Error).self) {
            try PairingSecrets.open(message, tag: tag, privateKey: Curve25519.KeyAgreement.PrivateKey(), codeKey: codeKey)
        }
        // The server's key is vouched for by the code's tag.
        let keyTag = PairingCode.tag(server.publicKey.rawRepresentation, key: codeKey)
        #expect(PairingCode.isValid(tag: keyTag, for: server.publicKey.rawRepresentation, key: codeKey))
        #expect(!PairingCode.isValid(tag: keyTag, for: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation, key: codeKey))
    }
}
