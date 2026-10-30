import Foundation
import Testing
@testable import FernsyCore

/// The account key (add-recording-cloud 3.2, cloud-account-from-icloud-key 2.2): two creators end
/// with one key, only an answered "absent" lets a device create one, and the Mac marker.
struct CloudKeyStoreTests {
    struct Unreachable: Error {}

    /// CloudKit's "save only if absent", with a pause so two creators really overlap.
    actor FakeCloud: CloudKeyBacking {
        var stored: Data?
        var saves = 0
        var failing = false
        var marker: Date?
        var markerSaves = 0
        func setFailing(_ value: Bool) { failing = value }
        func load() async throws -> Data? {
            if failing { throw Unreachable() }
            return stored
        }
        func saveIfAbsent(_ payload: Data) async throws -> Data {
            try await Task.sleep(for: .milliseconds(20))
            saves += 1
            if let stored { return stored }
            stored = payload
            return payload
        }
        nonisolated func isAvailable() async -> Bool { true }
        func loadMacMarker() async throws -> Date? {
            if failing { throw Unreachable() }
            return marker
        }
        func saveMacMarker(_ date: Date) async throws {
            markerSaves += 1
            marker = date
        }
    }

    final class Stamp: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date?
        func load() -> Date? { lock.withLock { date } }
        func save(_ value: Date) { lock.withLock { date = value } }
    }

    final class LocalKeychain: @unchecked Sendable {
        private let lock = NSLock()
        private var key: CloudAccountKey?
        func load() -> CloudAccountKey? { lock.withLock { key } }
        func save(_ value: CloudAccountKey) { lock.withLock { key = value } }
    }

    static func store(_ cloud: FakeCloud?, _ local: LocalKeychain) -> CloudKeyStore {
        CloudKeyStore(backing: cloud, loadLocal: { local.load() }, saveLocal: { local.save($0) })
    }

    @Test func racingCreatorsShareOneKey() async throws {
        let cloud = FakeCloud()
        let macA = Self.store(cloud, LocalKeychain()), macB = Self.store(cloud, LocalKeychain())
        async let a = macA.createIfMissing()
        async let b = macB.createIfMissing()
        let (keyA, keyB) = try await (a, b)
        #expect(keyA == keyB)
        #expect(await cloud.saves == 2)
    }

    @Test func readerNeverCreates() async throws {
        let cloud = FakeCloud()
        let local = LocalKeychain()
        let tv = Self.store(cloud, local)
        #expect(await tv.key() == nil)
        #expect(await tv.lookup() == .absent)
        #expect(await cloud.stored == nil)
        // Once the Mac made one, the reader finds it and keeps it locally.
        let created = try await Self.store(cloud, LocalKeychain()).createIfMissing()
        #expect(await tv.key() == created)
        #expect(local.load() == created)
    }

    @Test func localOnlyWithoutBacking() async throws {
        let local = LocalKeychain()
        let store = Self.store(nil, local)
        #expect(await store.key() == nil)
        let key = try await store.createIfMissing()
        #expect(try await store.createIfMissing() == key)
    }

    /// Design D: an iCloud error is "locked", and a locked device never makes a second key.
    @Test func errorNeverCreatesAKey() async throws {
        let cloud = FakeCloud()
        let existing = try await Self.store(cloud, LocalKeychain()).createIfMissing()
        await cloud.setFailing(true)
        let ipad = Self.store(cloud, LocalKeychain())
        #expect(await ipad.lookup() == .locked)
        await #expect(throws: CloudKeyStore.Locked.self) { try await ipad.createIfMissing() }
        #expect(await cloud.saves == 1)
        await cloud.setFailing(false)
        #expect(try await ipad.createIfMissing() == existing)
    }

    /// Design F: the Mac writes the marker at most once a day; others read known, unknown or unavailable.
    @Test func macMarker() async throws {
        let cloud = FakeCloud()
        let stamp = Stamp()
        let mac = CloudKeyStore(backing: cloud, loadLocal: { nil }, saveLocal: { _ in },
                                macMarkedAt: { stamp.load() }, setMacMarkedAt: { stamp.save($0) })
        let tv = Self.store(cloud, LocalKeychain())
        #expect(await tv.macPresence() == .unknown)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        await mac.markMac(now: now)
        await mac.markMac(now: now.addingTimeInterval(3600))
        #expect(await cloud.markerSaves == 1)
        await mac.markMac(now: now.addingTimeInterval(90_000))
        #expect(await cloud.markerSaves == 2)
        #expect(await tv.macPresence() == .known)
        await cloud.setFailing(true)
        #expect(await tv.macPresence() == .unavailable)
    }
}
