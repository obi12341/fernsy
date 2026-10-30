import Foundation
import Testing
@testable import FernsyCore

/// The Fernsy Cloud client (add-recording-cloud 3.3) against a stubbed server, and once against
/// the development server when `IPTV_CLOUD` and `IPTV_CLOUDTOKEN` are set.
@Suite(.serialized)
struct CloudClientTests {
    final class Stub: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?
        nonisolated(unsafe) static var requests: [URLRequest] = []
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.requests.append(request)
            let (status, headers, body) = Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    static func client(_ credential: CloudClient.Credential) -> CloudClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return CloudClient(baseURL: URL(string: "https://cloud.test")!, urlSession: URLSession(configuration: config), credential: credential)
    }

    static func json(_ text: String) -> Data { Data(text.utf8) }

    /// cloud-account-from-icloud-key 2.3: the key's account id and access secret in every request.
    @Test func accountWithKeyCredential() async throws {
        Stub.requests = []
        Stub.handler = { _ in
            (200, [:], Self.json(#"{"userId":"u1","state":"grace","expiresAt":"2026-10-01T10:00:00.000Z","endedAt":"2026-10-01T10:00:00Z","deleteAt":"2026-10-31T10:00:00.000Z","usedBytes":100,"totalBytes":1000}"#))
        }
        let client = Self.client(.none)
        await #expect(throws: CloudClient.Failure.noAccount) { try await client.account() }
        #expect(Stub.requests.isEmpty)
        let key = CloudAccountKey(id: "0F8FAD5B-D9CB-469F-A165-70867728950E", raw: Data(0..<32))
        client.use(key)
        #expect(client.hasAccount)
        let account = try await client.account()
        #expect(account.state == .grace)
        #expect(account.canPlay && !account.canUpload)
        #expect(account.freeBytes == 900)
        #expect(account.deleteAt == CloudDates.parse("2026-10-31T10:00:00Z"))
        // base64url of the fixed vector in CloudCryptoTests.accountCredential, without padding.
        #expect(Stub.requests.last?.value(forHTTPHeaderField: "Authorization")
                == "Key 0f8fad5b-d9cb-469f-a165-70867728950e:3wnfwpxsQdBEq2PNSALkepvwhZ0rXFl4xdDj9wJBxAc")
    }

    @Test func devTokenStaysWhenAKeyArrives() async throws {
        Stub.requests = []
        Stub.handler = { _ in (200, [:], Self.json(#"{"recordings":[]}"#)) }
        let client = Self.client(.dev("devtoken"))
        client.use(CloudAccountKey())
        _ = try await client.recordings()
        #expect(Stub.requests.last?.value(forHTTPHeaderField: "Authorization") == "Dev devtoken")
    }

    @Test func errorsAreMapped() async throws {
        let client = Self.client(.dev("devtoken"))
        Stub.handler = { _ in (413, [:], Self.json(#"{"error":"quota","neededBytes":3000,"freeBytes":1000}"#)) }
        await #expect(throws: CloudClient.Failure.quota(needed: 3000, free: 1000)) { try await client.startUpload(dataBytes: 3000, metaBytes: 10) }
        Stub.handler = { _ in (402, [:], Self.json(#"{"error":"no_subscription"}"#)) }
        await #expect(throws: CloudClient.Failure.noSubscription) { try await client.startUpload(dataBytes: 1, metaBytes: 1) }
        Stub.handler = { _ in (404, [:], Self.json(#"{"error":"not_found"}"#)) }
        await #expect(throws: CloudClient.Failure.notFound) { try await client.readURLs(id: "x") }
        Stub.handler = { _ in (409, [:], Self.json(#"{"error":"other_account"}"#)) }
        await #expect(throws: CloudClient.Failure.otherAccount) { try await client.linkSubscription(originalTransactionId: "1") }
        Stub.handler = { _ in (401, [:], Self.json(#"{"error":"unauthorized"}"#)) }
        await #expect(throws: CloudClient.Failure.accountConflict) { try await client.recordings() }
    }

    @Test func moveAndDelete() async throws {
        Stub.requests = []
        let client = Self.client(.dev("t"))
        Stub.handler = { request in
            if request.httpMethod == "DELETE" { return (200, [:], Self.json("{}")) }
            let body = try! JSONSerialization.jsonObject(with: Self.body(of: request)) as! [String: Any]
            #expect(body["originalTransactionId"] as? String == "2000000000000001")
            #expect(body["move"] as? Bool == true)
            return (200, [:], Self.json(#"{"state":"active","usedBytes":0,"totalBytes":1}"#))
        }
        #expect(try await client.linkSubscription(originalTransactionId: "2000000000000001", move: true).state == .active)
        try await client.deleteAccount()
        #expect(Stub.requests.last?.httpMethod == "DELETE")
        #expect(Stub.requests.last?.url?.path == "/v1/account")
    }

    @Test func uploadAnswerDecodes() async throws {
        let client = Self.client(.dev("t"))
        Stub.handler = { request in
            let body = try! JSONSerialization.jsonObject(with: Self.body(of: request)) as! [String: Any]
            #expect(body["partSize"] as? Int == CloudCrypto.partSize)
            return (200, [:], Self.json(#"{"id":"r1","uploadId":"up","partSize":16777472,"partCount":2,"partURLs":[{"number":1,"url":"https://r2.test/1"},{"number":2,"url":"https://r2.test/2"}],"metaURL":"https://r2.test/meta"}"#))
        }
        let upload = try await client.startUpload(dataBytes: 20_000_000, metaBytes: 300)
        #expect(upload.partURLs.map(\.number) == [1, 2])
        #expect(upload.metaURL.absoluteString == "https://r2.test/meta")
    }

    /// URLProtocol gets the body as a stream.
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    static let liveEnv = ProcessInfo.processInfo.environment

    /// Against the development server: account, a tiny upload, list, read and delete.
    @Test(.enabled(if: liveEnv["IPTV_CLOUD"] != nil && liveEnv["IPTV_CLOUDTOKEN"] != nil))
    func liveDevelopmentServer() async throws {
        let client = CloudClient(baseURL: URL(string: Self.liveEnv["IPTV_CLOUD"]!)!, credential: .dev(Self.liveEnv["IPTV_CLOUDTOKEN"]!))
        let account = try await client.account()
        #expect(account.totalBytes > 0)
        let plain = Data((0..<(6 * CloudCrypto.chunkSize)).map { UInt8(truncatingIfNeeded: $0) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID()).ts")
        try plain.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let accountKey = CloudAccountKey()
        let fileKey = CloudCrypto.newFileKey()
        let layout = CloudFileLayout(plaintextSize: Int64(plain.count))
        let metaPlaceholder = CloudRecordingMeta(title: "Live test", channel: "Test", showStart: nil, showEnd: nil, recordStart: .now,
                                                 recordEnd: .now, plaintextBytes: Int64(plain.count), fileKey: fileKey.withUnsafeBytes { Data($0) })
        let metaSize = try CloudCrypto.sealMeta(metaPlaceholder, accountKey: accountKey, recordingId: "00000000-0000-0000-0000-000000000000").count
        let upload = try await client.startUpload(dataBytes: layout.ciphertextSize, metaBytes: Int64(metaSize))
        let encryptor = try CloudFileEncryptor(url: url, plaintextSize: Int64(plain.count), key: fileKey, recordingId: upload.id)
        var parts: [CloudClient.CompletedPart] = []
        for part in upload.partURLs {
            var request = URLRequest(url: part.url)
            request.httpMethod = "PUT"
            let (_, response) = try await URLSession.shared.upload(for: request, from: try encryptor.bytes(in: layout.range(ofPart: part.number)))
            let http = response as! HTTPURLResponse
            #expect(http.statusCode == 200)
            parts.append(.init(number: part.number, etag: http.value(forHTTPHeaderField: "ETag") ?? ""))
        }
        var metaRequest = URLRequest(url: upload.metaURL)
        metaRequest.httpMethod = "PUT"
        let meta = try CloudCrypto.sealMeta(metaPlaceholder, accountKey: accountKey, recordingId: upload.id)
        #expect(meta.count == metaSize)
        _ = try await URLSession.shared.upload(for: metaRequest, from: meta)
        try await client.complete(id: upload.id, parts: parts)
        #expect(try await client.recordings().contains { $0.id == upload.id })
        let urls = try await client.readURLs(id: upload.id)
        var ranged = URLRequest(url: urls.dataURL)
        let chunk = layout.ciphertextRange(ofChunk: 3)
        ranged.setValue("bytes=\(chunk.lowerBound)-\(chunk.upperBound - 1)", forHTTPHeaderField: "Range")
        let (sealed, _) = try await URLSession.shared.data(for: ranged)
        let opened = try CloudCrypto.openChunk(sealed, index: 3, isLast: false, key: fileKey, recordingId: upload.id)
        #expect(opened == plain[3 * CloudCrypto.chunkSize..<4 * CloudCrypto.chunkSize])
        let (metaData, _) = try await URLSession.shared.data(from: urls.metaURL)
        #expect(try CloudCrypto.openMeta(metaData, accountKey: accountKey, recordingId: upload.id).title == "Live test")
        try await client.delete(id: upload.id)
        #expect(try await client.recordings().contains { $0.id == upload.id } == false)
    }

    /// Not a check: uploads the UI tests' fixture (`FERNSY_CLOUD_FIXTURE=<.ts file>`) to the
    /// development server, sealed with the key in `IPTV_CLOUDKEY` (base64 key JSON), and keeps it.
    /// The UI tests launch the apps with the same key. See DEVELOPMENT.md › Fernsy Cloud.
    @Test(.enabled(if: liveEnv["FERNSY_CLOUD_FIXTURE"] != nil && liveEnv["IPTV_CLOUDKEY"] != nil && liveEnv["IPTV_CLOUD"] != nil))
    func uploadUITestFixture() async throws {
        let client = CloudClient(baseURL: URL(string: Self.liveEnv["IPTV_CLOUD"]!)!, credential: .dev(Self.liveEnv["IPTV_CLOUDTOKEN"]!))
        let keyData = try #require(Data(base64Encoded: Self.liveEnv["IPTV_CLOUDKEY"]!))
        let accountKey = try JSONDecoder().decode(CloudAccountKey.self, from: keyData)
        let url = URL(fileURLWithPath: Self.liveEnv["FERNSY_CLOUD_FIXTURE"]!)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int64
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let meta = CloudRecordingMeta(title: "Cloud Fixture", channel: "Northern Light 1", showStart: start, showEnd: start.addingTimeInterval(660),
                                      recordStart: start, recordEnd: start.addingTimeInterval(660), plaintextBytes: size,
                                      fileKey: CloudCrypto.newFileKey().withUnsafeBytes { Data($0) })
        let keys = CloudKeyStore(backing: nil, loadLocal: { accountKey }, saveLocal: { _ in })
        let queue = await CloudUploadQueue(api: client, keys: keys, stateURL: nil)
        let local = UUID()
        await queue.enqueue(id: local, fileURL: url, meta: meta)
        for _ in 0..<600 {
            if await queue.uploaded[local] != nil { break }
            if let job = await queue.job(for: local), job.state == .failed { Issue.record("upload failed: \(job.message ?? "")"); return }
            try await Task.sleep(for: .milliseconds(500))
        }
        let id = try #require(await queue.uploaded[local])
        print("FIXTURE_ID \(id)")
    }
}
