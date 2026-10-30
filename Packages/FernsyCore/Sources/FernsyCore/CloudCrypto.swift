import CryptoKit
import Foundation

/// End-to-end encryption of Fernsy Cloud recordings (add-recording-cloud design A/B).
///
/// A recording's data object is a 16-byte header (`FCR1`, version, chunk size) followed by
/// chunks of 1 MiB plaintext, each sealed with AES-256-GCM under the recording's own file key.
/// The nonce is the chunk index, the AAD binds the recording id, the index and whether it is the
/// last chunk, so changed, swapped or cut-off chunks fail to open. A plaintext offset maps to a
/// chunk and a chunk to its ciphertext range, so players can seek without a full download.
///
/// The details (`CloudRecordingMeta`, including the file key) are sealed under the account key,
/// which never leaves the user's devices and iCloud.
public enum CloudCrypto {
    public static let chunkSize = 1 << 20
    public static let tagSize = 16
    public static let sealedChunkSize = chunkSize + tagSize
    public static let headerSize = 16
    /// Upload parts: every part has this size except the last (R2 needs equal parts).
    public static let partSize = 16 * sealedChunkSize
    static let version: UInt8 = 1

    public enum Failure: Error, Equatable {
        /// Not a Fernsy Cloud file, or a format this version cannot read.
        case badHeader
        /// A chunk or the details failed authentication: changed, swapped, cut off or another key.
        case damaged
        /// The details were sealed with an account key this device does not have.
        case unknownKey(String)
    }

    // MARK: Data object

    public static func header() -> Data {
        var data = Data("FCR1".utf8)
        data.append(version)
        data.append(contentsOf: [0, 0, 0])
        withUnsafeBytes(of: UInt32(chunkSize).bigEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0, 0, 0, 0])
        return data
    }

    public static func checkHeader(_ data: Data) throws {
        guard data.count >= headerSize, data.prefix(4) == Data("FCR1".utf8), data[data.startIndex + 4] == version else {
            throw Failure.badHeader
        }
        let size = data.dropFirst(8).prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard size == UInt32(chunkSize) else { throw Failure.badHeader }
    }

    public static func newFileKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func nonce(_ index: Int) -> AES.GCM.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        withUnsafeBytes(of: UInt64(index).bigEndian) { bytes.replaceSubrange(4..<12, with: $0) }
        return try! AES.GCM.Nonce(data: bytes)
    }

    static func chunkAAD(_ recordingId: String, _ index: Int, _ isLast: Bool) -> Data {
        Data("\(recordingId)|\(index)|\(isLast ? 1 : 0)".utf8)
    }

    /// Ciphertext and tag of one chunk (the nonce is not stored, it is the index).
    public static func sealChunk(_ plain: Data, index: Int, isLast: Bool, key: SymmetricKey, recordingId: String) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key, nonce: nonce(index), authenticating: chunkAAD(recordingId, index, isLast))
        var sealed = Data(box.ciphertext)
        sealed.append(box.tag)
        return sealed
    }

    public static func openChunk(_ sealed: Data, index: Int, isLast: Bool, key: SymmetricKey, recordingId: String) throws -> Data {
        guard sealed.count >= tagSize else { throw Failure.damaged }
        do {
            let box = try AES.GCM.SealedBox(nonce: nonce(index), ciphertext: sealed.dropLast(tagSize), tag: sealed.suffix(tagSize))
            return try AES.GCM.open(box, using: key, authenticating: chunkAAD(recordingId, index, isLast))
        } catch {
            throw Failure.damaged
        }
    }

    // MARK: Details

    /// `FCM1`, key id length, key id, then AES-GCM's combined form (nonce, ciphertext, tag).
    public static func sealMeta(_ meta: CloudRecordingMeta, accountKey: CloudAccountKey, recordingId: String) throws -> Data {
        let json = try JSONEncoder.cloud.encode(meta)
        let keyId = Data(accountKey.id.utf8)
        let box = try AES.GCM.seal(json, using: accountKey.key, authenticating: metaAAD(recordingId, accountKey.id))
        var data = Data("FCM1".utf8)
        data.append(UInt8(keyId.count))
        data.append(keyId)
        data.append(box.combined!)
        return data
    }

    /// The account key id a sealed details object needs.
    public static func metaKeyId(_ data: Data) throws -> String {
        guard data.count > 5, data.prefix(4) == Data("FCM1".utf8) else { throw Failure.badHeader }
        let length = Int(data[data.startIndex + 4])
        guard data.count > 5 + length, let id = String(data: data.dropFirst(5).prefix(length), encoding: .utf8) else { throw Failure.badHeader }
        return id
    }

    public static func openMeta(_ data: Data, accountKey: CloudAccountKey, recordingId: String) throws -> CloudRecordingMeta {
        let keyId = try metaKeyId(data)
        guard keyId == accountKey.id else { throw Failure.unknownKey(keyId) }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(5 + Data(keyId.utf8).count))
            let json = try AES.GCM.open(box, using: accountKey.key, authenticating: metaAAD(recordingId, keyId))
            return try JSONDecoder.cloud.decode(CloudRecordingMeta.self, from: json)
        } catch {
            throw Failure.damaged
        }
    }

    static func metaAAD(_ recordingId: String, _ keyId: String) -> Data { Data("fernsy-meta-v1|\(recordingId)|\(keyId)".utf8) }
}

/// Where a recording's plaintext lives in its encrypted data object.
public struct CloudFileLayout: Equatable, Sendable {
    public let plaintextSize: Int64

    public init(plaintextSize: Int64) { self.plaintextSize = plaintextSize }

    public init(ciphertextSize: Int64) {
        let body = max(0, ciphertextSize - Int64(CloudCrypto.headerSize))
        let full = body / Int64(CloudCrypto.sealedChunkSize)
        let rest = body % Int64(CloudCrypto.sealedChunkSize)
        plaintextSize = full * Int64(CloudCrypto.chunkSize) + max(0, rest - Int64(CloudCrypto.tagSize))
    }

    public var chunkCount: Int { Int((plaintextSize + Int64(CloudCrypto.chunkSize) - 1) / Int64(CloudCrypto.chunkSize)) }
    public var ciphertextSize: Int64 {
        Int64(CloudCrypto.headerSize) + plaintextSize + Int64(chunkCount) * Int64(CloudCrypto.tagSize)
    }
    public var partCount: Int { Int((ciphertextSize + Int64(CloudCrypto.partSize) - 1) / Int64(CloudCrypto.partSize)) }

    public func chunk(containing plaintextOffset: Int64) -> Int { Int(plaintextOffset / Int64(CloudCrypto.chunkSize)) }
    public func plaintextRange(ofChunk index: Int) -> Range<Int64> {
        let start = Int64(index) * Int64(CloudCrypto.chunkSize)
        return start..<min(plaintextSize, start + Int64(CloudCrypto.chunkSize))
    }
    public func ciphertextRange(ofChunk index: Int) -> Range<Int64> {
        let start = Int64(CloudCrypto.headerSize) + Int64(index) * Int64(CloudCrypto.sealedChunkSize)
        return start..<(start + Int64(plaintextRange(ofChunk: index).count) + Int64(CloudCrypto.tagSize))
    }
    public func isLast(_ index: Int) -> Bool { index == chunkCount - 1 }
    /// Byte range of upload part `number` (1-based) in the data object.
    public func range(ofPart number: Int) -> Range<Int64> {
        let start = Int64(number - 1) * Int64(CloudCrypto.partSize)
        return start..<min(ciphertextSize, start + Int64(CloudCrypto.partSize))
    }
}

/// Produces any byte range of a recording's encrypted data object from the plaintext file, so
/// an upload part can be recomputed after a restart (design D). AES-GCM with the index nonce is
/// deterministic for a given file key.
public final class CloudFileEncryptor {
    public let layout: CloudFileLayout
    private let handle: FileHandle
    private let key: SymmetricKey
    private let recordingId: String

    public init(url: URL, plaintextSize: Int64, key: SymmetricKey, recordingId: String) throws {
        handle = try FileHandle(forReadingFrom: url)
        layout = CloudFileLayout(plaintextSize: plaintextSize)
        self.key = key
        self.recordingId = recordingId
    }

    deinit { try? handle.close() }

    public func bytes(in range: Range<Int64>) throws -> Data {
        var out = Data()
        out.reserveCapacity(range.count)
        let header = CloudCrypto.header()
        if range.lowerBound < Int64(header.count) {
            out.append(header[Int(range.lowerBound)..<Int(min(Int64(header.count), range.upperBound))])
        }
        let body = max(range.lowerBound, Int64(CloudCrypto.headerSize))
        guard body < range.upperBound, layout.chunkCount > 0 else { return out }
        let first = Int((body - Int64(CloudCrypto.headerSize)) / Int64(CloudCrypto.sealedChunkSize))
        let last = Int((range.upperBound - 1 - Int64(CloudCrypto.headerSize)) / Int64(CloudCrypto.sealedChunkSize))
        for index in first...min(last, layout.chunkCount - 1) {
            let plain = layout.plaintextRange(ofChunk: index)
            try handle.seek(toOffset: UInt64(plain.lowerBound))
            guard let data = try handle.read(upToCount: plain.count), data.count == plain.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let sealed = try CloudCrypto.sealChunk(data, index: index, isLast: layout.isLast(index), key: key, recordingId: recordingId)
            let chunkRange = layout.ciphertextRange(ofChunk: index)
            let from = max(range.lowerBound, chunkRange.lowerBound) - chunkRange.lowerBound
            let to = min(range.upperBound, chunkRange.upperBound) - chunkRange.lowerBound
            out.append(sealed[sealed.startIndex + Int(from)..<sealed.startIndex + Int(to)])
        }
        return out
    }
}

/// The account key: random 256 bit, with an id so details name the key they need.
public struct CloudAccountKey: Codable, Equatable, Sendable {
    public let id: String
    public let raw: Data

    public init(id: String = UUID().uuidString, raw: Data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }) {
        self.id = id
        self.raw = raw
    }

    public var key: SymmetricKey { SymmetricKey(data: raw) }

    /// The Fernsy Cloud account this key belongs to (cloud-account-from-icloud-key design A);
    /// also the purchase's `appAccountToken`.
    public var accountId: String { id.lowercased() }

    /// Proves the account to the server, which keeps only its SHA-256. Derived with its own
    /// salt, so neither it nor its hash leads back to the encryption key.
    public var accessSecret: Data {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: Data("fernsy-cloud-account-v1".utf8),
                               info: Data(accountId.utf8), outputByteCount: 32)
            .withUnsafeBytes { Data($0) }
    }
}

/// A cloud recording's details, readable only on the user's devices.
public struct CloudRecordingMeta: Codable, Equatable, Sendable {
    public struct Gap: Codable, Equatable, Sendable {
        public var start: Date
        public var seconds: Double
        public init(start: Date, seconds: Double) {
            self.start = start
            self.seconds = seconds
        }
    }

    public var title: String
    public var channel: String
    public var showStart: Date?
    public var showEnd: Date?
    public var recordStart: Date
    public var recordEnd: Date
    public var plaintextBytes: Int64
    public var gaps: [Gap]
    /// The local recording's outcome ("completed", "partial", …), shown as on the Mac.
    public var outcome: String
    /// The file key (32 bytes); only ever inside the sealed details.
    public var fileKey: Data

    public init(title: String, channel: String, showStart: Date?, showEnd: Date?, recordStart: Date, recordEnd: Date,
                plaintextBytes: Int64, gaps: [Gap] = [], outcome: String = "completed", fileKey: Data) {
        self.title = title
        self.channel = channel
        self.showStart = showStart
        self.showEnd = showEnd
        self.recordStart = recordStart
        self.recordEnd = recordEnd
        self.plaintextBytes = plaintextBytes
        self.gaps = gaps
        self.outcome = outcome
        self.fileKey = fileKey
    }

    public var duration: TimeInterval { recordEnd.timeIntervalSince(recordStart) }
    public var key: SymmetricKey { SymmetricKey(data: fileKey) }
}

extension JSONEncoder {
    static var cloud: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var cloud: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = CloudDates.parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(text)"))
        }
        return decoder
    }
}

/// ISO 8601 with or without fractional seconds (the worker sends `toISOString()`).
enum CloudDates {
    static func parse(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
