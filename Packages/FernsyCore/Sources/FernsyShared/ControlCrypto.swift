#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#else
import CryptoExtras
#endif
import Foundation

/// The key the apps and a paired Fernsy Server share for Fernsy Control (headless-recorder
/// design 3). It never leaves the user's devices, iCloud and the paired server; the worker only
/// sees what is derived from it with HKDF under separate salts: the space id, the write secret
/// (as its hash) and ciphertext sealed with the item key.
public struct ControlKey: Codable, Equatable, Sendable {
    public let raw: Data

    public init(raw: Data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }) {
        self.raw = raw
    }

    private func derive(_ salt: String, _ count: Int) -> Data {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: raw), salt: Data(salt.utf8),
                               info: Data(), outputByteCount: count)
            .withUnsafeBytes { Data($0) }
    }

    /// 32 lowercase hex characters naming the space on the worker.
    public var spaceId: String { derive("fernsy-control-space-v1", 16).map { String(format: "%02x", $0) }.joined() }

    public var writeSecret: Data { derive("fernsy-control-write-v1", 32) }

    var itemKey: SymmetricKey { SymmetricKey(data: derive("fernsy-control-items-v1", 32)) }

    /// `Authorization` header value for the worker's item routes.
    public var authorization: String { "Space \(spaceId):\(writeSecret.base64URL)" }

    /// AES-GCM (nonce, ciphertext, tag); the AAD binds the item to its kind and id.
    public func seal(_ plaintext: Data, kind: String, id: String) throws -> Data {
        try AES.GCM.seal(plaintext, using: itemKey, authenticating: Data("\(kind)/\(id)".utf8)).combined!
    }

    public func open(_ sealed: Data, kind: String, id: String) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: itemKey, authenticating: Data("\(kind)/\(id)".utf8))
    }
}

/// The ten-character code a Fernsy Server shows for pairing (design 4): Crockford base32, the
/// first four characters name the mailbox on the worker, the other six are the secret the worker
/// never sees. The key derived from the secret authenticates the server's public key and the
/// app's answer, so neither a worker that swaps keys nor someone who guessed a mailbox can pair.
public struct PairingCode: Equatable, Sendable {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    /// Slow on purpose: guessing the six secret characters offline must take longer than the
    /// mailbox lives (15 minutes).
    public static let rounds = 600_000

    /// The ten characters without separator.
    public let value: String

    public init() {
        value = String((0..<10).map { _ in Self.alphabet.randomElement()! })
    }

    /// Accepts what a person types: any case, spaces and dashes, and Crockford's look-alikes
    /// (O → 0, I and L → 1).
    public init?(_ text: String) {
        let mapped = text.uppercased().compactMap { c -> Character? in
            switch c {
            case " ", "-": return nil
            case "O": return "0"
            case "I", "L": return "1"
            default: return c
            }
        }
        guard mapped.count == 10, mapped.allSatisfy(Self.alphabet.contains) else { return nil }
        value = String(mapped)
    }

    /// `XXXX-XXXXXX`, as the server shows it.
    public var display: String { "\(value.prefix(4))-\(value.dropFirst(4))" }

    public var mailbox: String { String(value.prefix(4)) }

    /// PBKDF2-HMAC-SHA256 of the secret part, salted with the mailbox.
    public func key(rounds: Int = Self.rounds) throws -> SymmetricKey {
        try pbkdf2SHA256(password: Data(value.dropFirst(4).utf8), salt: Data("fernsy-pairing-v1/\(mailbox)".utf8),
                         rounds: rounds, count: 32)
    }

    public static func tag(_ data: Data, key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    public static func isValid(tag: Data, for data: Data, key: SymmetricKey) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: data, using: key)
    }
}

/// What an app hands a server when pairing: sealed to the server's X25519 key with HPKE
/// (RFC 9180, DHKEM X25519 / HKDF-SHA256 / ChaCha20-Poly1305) and tagged with the pairing code's key.
public struct PairingSecrets: Codable, Equatable, Sendable {
    public var controlKey: ControlKey
    public var cloudKey: CloudAccountKey?
    public var login: XtreamCredentials

    public init(controlKey: ControlKey, cloudKey: CloudAccountKey?, login: XtreamCredentials) {
        self.controlKey = controlKey
        self.cloudKey = cloudKey
        self.login = login
    }

    static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    static let info = Data("fernsy-pairing-v1".utf8)

    public enum Failure: Error { case wrongTag }

    /// The message (encapsulated key followed by the ciphertext) and its tag.
    public func seal(to publicKey: Curve25519.KeyAgreement.PublicKey, codeKey: SymmetricKey) throws -> (message: Data, tag: Data) {
        var sender = try HPKE.Sender(recipientKey: publicKey, ciphersuite: Self.suite, info: Self.info)
        let message = sender.encapsulatedKey + (try sender.seal(try JSONEncoder().encode(self)))
        return (message, PairingCode.tag(message, key: codeKey))
    }

    public static func open(_ message: Data, tag: Data, privateKey: Curve25519.KeyAgreement.PrivateKey,
                            codeKey: SymmetricKey) throws -> PairingSecrets {
        guard PairingCode.isValid(tag: tag, for: message, key: codeKey) else { throw Failure.wrongTag }
        let encapsulatedKey = message.prefix(32), ciphertext = message.dropFirst(32)
        var recipient = try HPKE.Recipient(privateKey: privateKey, ciphersuite: suite, info: info,
                                           encapsulatedKey: Data(encapsulatedKey))
        return try JSONDecoder().decode(PairingSecrets.self, from: try recipient.open(Data(ciphertext)))
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// PBKDF2-HMAC-SHA256: CommonCrypto on Apple platforms (no BoringSSL in the apps), swift-crypto's
/// CryptoExtras on Linux.
func pbkdf2SHA256(password: Data, salt: Data, rounds: Int, count: Int) throws -> SymmetricKey {
    #if canImport(CommonCrypto)
    var out = Data(count: count)
    let status = out.withUnsafeMutableBytes { outBytes in
        password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                                     saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                                     outBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), count)
            }
        }
    }
    guard status == kCCSuccess else { throw CocoaError(.coderInvalidValue) }
    return SymmetricKey(data: out)
    #else
    return try KDF.Insecure.PBKDF2.deriveKey(from: password, salt: salt, using: .sha256, outputByteCount: count,
                                             unsafeUncheckedRounds: rounds)
    #endif
}
