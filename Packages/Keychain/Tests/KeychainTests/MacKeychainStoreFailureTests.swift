import Foundation
@testable import Keychain
import Security
import Testing
import TestUtils

@Suite("Mac keychain failures")
struct MacKeychainStoreFailureTests {
    private let session = Data(TestStorageKey.session.utf8)
    private let outdated = Data(TestValue.outdated.utf8)

    private func makeStore(modern: FakeKeychainStore, legacy: FakeKeychainStore) -> MacKeychainStore {
        MacKeychainStore(modern: modern, legacy: legacy)
    }

    @Test("a save that fails for another reason than the entitlement is thrown and leaves the legacy copy")
    func saveRethrowsOtherFailures() {
        let modern = FakeKeychainStore()
        modern.fail(.save, with: Constants.locked)
        let legacy = FakeKeychainStore(items: [TestStorageKey.session: outdated])

        #expect(throws: Constants.locked) {
            try makeStore(modern: modern, legacy: legacy).save(key: TestStorageKey.session, data: session)
        }
        #expect(legacy.contents[TestStorageKey.session] == outdated)
        #expect(!legacy.calls.contains("delete \(TestStorageKey.session)"))
    }

    @Test("a read that fails for another reason than the entitlement is thrown without touching the legacy keychain")
    func loadRethrowsOtherFailures() {
        let modern = FakeKeychainStore()
        modern.fail(.load, with: Constants.locked)
        let legacy = FakeKeychainStore(items: [TestStorageKey.session: session])

        #expect(throws: Constants.locked) {
            _ = try makeStore(modern: modern, legacy: legacy).load(key: TestStorageKey.session)
        }
        #expect(legacy.calls.isEmpty)
        #expect(legacy.contents[TestStorageKey.session] == session)
    }

    @Test("a legacy read failure after a clean miss is thrown")
    func legacyLoadFailureIsThrown() {
        let legacy = FakeKeychainStore()
        legacy.fail(.load, with: Constants.locked)

        #expect(throws: Constants.locked) {
            _ = try makeStore(modern: FakeKeychainStore(), legacy: legacy).load(key: TestStorageKey.session)
        }
    }

    @Test("a failed move on read still returns the session and keeps the legacy copy for the next read")
    func failedMoveKeepsLegacyCopy() throws {
        let modern = FakeKeychainStore()
        modern.fail(.save, with: Constants.locked)
        let legacy = FakeKeychainStore(items: [TestStorageKey.session: session])

        #expect(try makeStore(modern: modern, legacy: legacy).load(key: TestStorageKey.session) == session)
        #expect(legacy.contents[TestStorageKey.session] == session)
        #expect(modern.contents.isEmpty)
    }

    @Test("a delete clears the legacy copy even when the data protection delete fails, then reports that failure")
    func deleteReportsModernFailureAfterClearingLegacy() {
        let modern = FakeKeychainStore(items: [TestStorageKey.session: session])
        modern.fail(.delete, with: Constants.locked)
        let legacy = FakeKeychainStore(items: [TestStorageKey.session: session])

        #expect(throws: Constants.locked) {
            try makeStore(modern: modern, legacy: legacy).delete(key: TestStorageKey.session)
        }
        #expect(legacy.contents.isEmpty)
    }

    @Test("eager migration skips an item it cannot read and still moves the others")
    func migrateAllSkipsUnreadableItem() {
        let modern = FakeKeychainStore()
        let legacy = FakeKeychainStore(items: [Constants.firstKey: session, Constants.secondKey: outdated])
        legacy.fail(.load, key: Constants.firstKey, with: Constants.locked)

        #expect(makeStore(modern: modern, legacy: legacy).migrateAll() == 1)
        #expect(modern.contents == [Constants.secondKey: outdated])
        #expect(legacy.contents == [Constants.firstKey: session])
    }

    @Test("eager migration keeps the legacy copy of an item it fails to write and still moves the others")
    func migrateAllKeepsLegacyCopyOnWriteFailure() {
        let modern = FakeKeychainStore()
        modern.fail(.save, key: Constants.firstKey, with: Constants.locked)
        let legacy = FakeKeychainStore(items: [Constants.firstKey: session, Constants.secondKey: outdated])

        #expect(makeStore(modern: modern, legacy: legacy).migrateAll() == 1)
        #expect(modern.contents == [Constants.secondKey: outdated])
        #expect(legacy.contents == [Constants.firstKey: session])
    }

    @Test("eager migration leaves an item whose data protection copy cannot be checked")
    func migrateAllKeepsLegacyCopyOnCheckFailure() {
        let modern = FakeKeychainStore()
        modern.fail(.load, with: Constants.locked)
        let legacy = FakeKeychainStore(items: [Constants.firstKey: session])

        #expect(makeStore(modern: modern, legacy: legacy).migrateAll() == 0)
        #expect(legacy.contents == [Constants.firstKey: session])
        #expect(modern.contents.isEmpty)
    }

    @Test("a keychain that cannot list its keys has nothing migrated from it")
    func migrateAllWithoutListing() {
        let legacy = FakeKeychainStore(items: [Constants.firstKey: session])
        legacy.fail(.allKeys, with: Constants.locked)
        #expect(makeStore(modern: FakeKeychainStore(), legacy: legacy).migrateAll() == 0)
        #expect(legacy.contents == [Constants.firstKey: session])
    }

    @Test("the real keychains round trip an item and a delete leaves nothing behind")
    func configurationInitializerUsesBothKeychains() throws {
        let store = MacKeychainStore(configuration: .unique())

        try store.save(key: TestStorageKey.session, data: session)
        #expect(try store.load(key: TestStorageKey.session) == session)
        try store.save(key: TestStorageKey.session, data: outdated)
        #expect(try store.load(key: TestStorageKey.session) == outdated)
        try store.delete(key: TestStorageKey.session)
        #expect(try store.load(key: TestStorageKey.session) == nil)
    }
}

private enum Constants {
    static let locked = KeychainError.unexpectedStatus(errSecInteractionNotAllowed)
    static let firstKey = "first"
    static let secondKey = "second"
}
