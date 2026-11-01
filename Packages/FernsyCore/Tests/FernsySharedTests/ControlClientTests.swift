#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Testing
@testable import FernsyShared

/// Against the dev deployment of Fernsy Control, only with `IPTV_CONTROL` set
/// (`https://fernsy-control-dev.mobilistics.workers.dev`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["IPTV_CONTROL"] != nil))
struct ControlClientLiveTests {
    let client = ControlClient.live()

    @Test func ordersAndStatesRoundTrip() async throws {
        let key = ControlKey()
        let order = ControlOrder(channelId: 101, channelName: "Demo 1", title: "Show", showStart: Date(timeIntervalSince1970: 1_800_000_000),
                                 showEnd: Date(timeIntervalSince1970: 1_800_003_600), padBefore: 120, padAfter: 300, createdBy: "Test")
        try await client.put(order, kind: .order, id: "o1", key: key)
        try await client.put(ControlOrderState(phase: .scheduled), kind: .state, id: "o1", key: key)
        let first = try await client.items(key, since: 0)
        #expect(first.change == 2)
        let item = try #require(first.items.first { $0.kind == "order" })
        #expect(try key.open(item, as: ControlOrder.self) == order)
        try await client.delete(kind: .order, id: "o1", key: key)
        let second = try await client.items(key, since: first.change)
        #expect(second.items.map(\.kind) == ["order"])
        #expect(second.items.first?.deleted == true)
        try await client.deleteSpace(key)
    }

    @Test func pairingThroughTheMailbox() async throws {
        let server = Curve25519.KeyAgreement.PrivateKey()
        var code = PairingCode()
        let claim = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let codeKey = try code.key(rounds: 1000)
        let keyTag = PairingCode.tag(server.publicKey.rawRepresentation, key: codeKey)
        while true {
            do { try await client.openMailbox(code, publicKey: server.publicKey.rawRepresentation, tag: keyTag, claim: claim); break }
            catch ControlClient.Failure.taken { code = PairingCode() }
        }
        #expect(try await client.pickUp(code, claim: claim) == nil)

        // The app, with the code the user typed.
        let typed = try #require(PairingCode(code.display.lowercased()))
        let typedKey = try typed.key(rounds: 1000)
        let box = try await client.mailbox(typed)
        #expect(PairingCode.isValid(tag: box.tag, for: box.publicKey, key: typedKey))
        let secrets = PairingSecrets(controlKey: ControlKey(), cloudKey: nil, login: XtreamCredentials(server: "s", username: "u", password: "p"))
        let sealed = try secrets.seal(to: try Curve25519.KeyAgreement.PublicKey(rawRepresentation: box.publicKey), codeKey: typedKey)
        try await client.answer(typed, message: sealed.message, tag: sealed.tag)

        let picked = try #require(try await client.pickUp(code, claim: claim))
        #expect(try PairingSecrets.open(picked.message, tag: picked.tag, privateKey: server, codeKey: codeKey) == secrets)
        await #expect(throws: ControlClient.Failure.notFound) { try await client.mailbox(code) }
    }
}
