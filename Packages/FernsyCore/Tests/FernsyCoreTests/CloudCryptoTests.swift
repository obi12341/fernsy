import CryptoKit
import Foundation
import Testing
@testable import FernsyCore

/// The FCR1 format (add-recording-cloud 3.1): round trip, ranges from the middle, and every kind
/// of tampering fails instead of handing altered data to the demuxer.
struct CloudCryptoTests {
    /// A fake MPEG-TS file: 188-byte packets starting with the sync byte 0x47.
    static func tsFile(bytes: Int) throws -> URL {
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for i in 0..<bytes { p[i] = i % 188 == 0 ? 0x47 : UInt8(truncatingIfNeeded: i &* 31 &+ i / 997) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID()).ts")
        try data.write(to: url)
        return url
    }

    /// The whole data object, part by part as an upload would produce it.
    static func encrypt(_ url: URL, key: SymmetricKey, id: String) throws -> Data {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int64
        let encryptor = try CloudFileEncryptor(url: url, plaintextSize: size, key: key, recordingId: id)
        var out = Data()
        for part in 1...max(1, encryptor.layout.partCount) { out.append(try encryptor.bytes(in: encryptor.layout.range(ofPart: part))) }
        return out
    }

    static func decrypt(_ object: Data, plaintextSize: Int64, key: SymmetricKey, id: String, chunks: Range<Int>? = nil) throws -> Data {
        try CloudCrypto.checkHeader(object)
        let layout = CloudFileLayout(plaintextSize: plaintextSize)
        var out = Data()
        for index in chunks ?? 0..<layout.chunkCount {
            let range = layout.ciphertextRange(ofChunk: index)
            guard range.upperBound <= Int64(object.count) else { throw CloudCrypto.Failure.damaged }
            out.append(try CloudCrypto.openChunk(object[Int(range.lowerBound)..<Int(range.upperBound)], index: index,
                                                 isLast: layout.isLast(index), key: key, recordingId: id))
        }
        return out
    }

    @Test func roundTripAcrossParts() throws {
        // Two full parts and a short third: 33 MiB + 5 bytes.
        let size = 33 * CloudCrypto.chunkSize + 5
        let url = try Self.tsFile(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let key = CloudCrypto.newFileKey()
        let object = try Self.encrypt(url, key: key, id: "rec-1")
        let layout = CloudFileLayout(plaintextSize: Int64(size))
        #expect(Int64(object.count) == layout.ciphertextSize)
        #expect(layout.partCount == 3)
        #expect(layout.range(ofPart: 1).count == CloudCrypto.partSize)
        #expect(layout.range(ofPart: 2).count == CloudCrypto.partSize)
        #expect(CloudFileLayout(ciphertextSize: layout.ciphertextSize) == layout)
        #expect(try Self.decrypt(object, plaintextSize: Int64(size), key: key, id: "rec-1") == Data(contentsOf: url))
    }

    @Test func rangeFromTheMiddle() throws {
        let size = 5 * CloudCrypto.chunkSize + 1234
        let url = try Self.tsFile(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let key = CloudCrypto.newFileKey()
        let object = try Self.encrypt(url, key: key, id: "rec-2")
        let layout = CloudFileLayout(plaintextSize: Int64(size))
        let offset: Int64 = 3 * Int64(CloudCrypto.chunkSize) + 500
        let index = layout.chunk(containing: offset)
        #expect(index == 3)
        let plain = try Self.decrypt(object, plaintextSize: Int64(size), key: key, id: "rec-2", chunks: index..<index + 1)
        let original = try Data(contentsOf: url)
        #expect(plain == original[Int(layout.plaintextRange(ofChunk: 3).lowerBound)..<Int(layout.plaintextRange(ofChunk: 3).upperBound)])
        // Any ciphertext range the encryptor produces matches the whole object at that place.
        let encryptor = try CloudFileEncryptor(url: url, plaintextSize: Int64(size), key: key, recordingId: "rec-2")
        let slice: Range<Int64> = 7..<(2 * Int64(CloudCrypto.sealedChunkSize) + 99)
        #expect(try encryptor.bytes(in: slice) == object[Int(slice.lowerBound)..<Int(slice.upperBound)])
    }

    @Test func tamperingFails() throws {
        let size = 3 * CloudCrypto.chunkSize + 77
        let url = try Self.tsFile(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let key = CloudCrypto.newFileKey()
        let object = try Self.encrypt(url, key: key, id: "rec-3")
        let layout = CloudFileLayout(plaintextSize: Int64(size))

        var changed = object
        changed[CloudCrypto.headerSize + 1000] ^= 0x01
        #expect(throws: CloudCrypto.Failure.damaged) { try Self.decrypt(changed, plaintextSize: Int64(size), key: key, id: "rec-3") }

        // Chunks 0 and 1 swapped.
        var swapped = object
        let a = layout.ciphertextRange(ofChunk: 0), b = layout.ciphertextRange(ofChunk: 1)
        swapped.replaceSubrange(Int(a.lowerBound)..<Int(a.upperBound), with: object[Int(b.lowerBound)..<Int(b.upperBound)])
        swapped.replaceSubrange(Int(b.lowerBound)..<Int(b.upperBound), with: object[Int(a.lowerBound)..<Int(a.upperBound)])
        #expect(throws: CloudCrypto.Failure.damaged) { try Self.decrypt(swapped, plaintextSize: Int64(size), key: key, id: "rec-3") }

        // Cut off after three full chunks: read as a file of three chunks, the third is not marked last.
        let cut = object.prefix(Int(layout.ciphertextRange(ofChunk: 2).upperBound))
        let shorter = CloudFileLayout(ciphertextSize: Int64(cut.count))
        #expect(throws: CloudCrypto.Failure.damaged) { try Self.decrypt(cut, plaintextSize: shorter.plaintextSize, key: key, id: "rec-3") }

        // Another recording id or key.
        #expect(throws: CloudCrypto.Failure.damaged) { try Self.decrypt(object, plaintextSize: Int64(size), key: key, id: "rec-4") }
        #expect(throws: CloudCrypto.Failure.damaged) { try Self.decrypt(object, plaintextSize: Int64(size), key: CloudCrypto.newFileKey(), id: "rec-3") }
    }

    @Test func noPlainTSVisible() throws {
        let size = 2 * CloudCrypto.chunkSize
        let url = try Self.tsFile(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let object = try Self.encrypt(url, key: CloudCrypto.newFileKey(), id: "rec-5")
        // A run of sync bytes 188 apart would mean plain TS packets.
        let body = [UInt8](object.dropFirst(CloudCrypto.headerSize))
        var runs = 0
        for start in 0..<188 where (0..<20).allSatisfy({ start + $0 * 188 < body.count && body[start + $0 * 188] == 0x47 }) { runs += 1 }
        #expect(runs == 0)
    }

    @Test func metaRoundTripAndTampering() throws {
        let account = CloudAccountKey()
        let fileKey = CloudCrypto.newFileKey().withUnsafeBytes { Data($0) }
        let meta = CloudRecordingMeta(title: "Tagesschau", channel: "Das Erste (DE)", showStart: Date(timeIntervalSince1970: 1_800_000_000),
                                      showEnd: Date(timeIntervalSince1970: 1_800_000_900), recordStart: Date(timeIntervalSince1970: 1_799_999_400),
                                      recordEnd: Date(timeIntervalSince1970: 1_800_001_500), plaintextBytes: 123,
                                      gaps: [.init(start: Date(timeIntervalSince1970: 1_800_000_100), seconds: 12)], fileKey: fileKey)
        let sealed = try CloudCrypto.sealMeta(meta, accountKey: account, recordingId: "rec-6")
        #expect(String(decoding: sealed, as: UTF8.self).contains("Tagesschau") == false)
        #expect(try CloudCrypto.metaKeyId(sealed) == account.id)
        #expect(try CloudCrypto.openMeta(sealed, accountKey: account, recordingId: "rec-6") == meta)
        #expect(throws: CloudCrypto.Failure.damaged) { try CloudCrypto.openMeta(sealed, accountKey: account, recordingId: "rec-7") }
        #expect(throws: CloudCrypto.Failure.unknownKey(account.id)) { try CloudCrypto.openMeta(sealed, accountKey: CloudAccountKey(), recordingId: "rec-6") }
    }

    /// The account credential (cloud-account-from-icloud-key 2.1): a fixed vector, computed
    /// independently with Python's hmac (RFC 5869), and never the raw key itself.
    @Test func accountCredential() throws {
        let key = CloudAccountKey(id: "0F8FAD5B-D9CB-469F-A165-70867728950E", raw: Data(0..<32))
        #expect(key.accountId == "0f8fad5b-d9cb-469f-a165-70867728950e")
        #expect(key.accessSecret.map { String(format: "%02x", $0) }.joined() == "df09dfc29c6c41d044ab63cd4802e47a9bf0859d2b5c5978c5d0e3f70241c407")
        #expect(key.accessSecret != key.raw)
        #expect(CloudAccountKey().accessSecret != CloudAccountKey().accessSecret)
    }
}
