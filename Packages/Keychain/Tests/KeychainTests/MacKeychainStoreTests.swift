import Foundation
@testable import Keychain
import Security
import Testing
import TestUtils

@Suite("Mac keychain migration")
struct MacKeychainStoreTests {
    private let session = Data(TestStorageKey.session.utf8)

    @Test("a session from the legacy keychain moves to the data protection keychain on first read")
    func legacyItemMovesOnRead() throws {
        let modern = FakeKeychainStore()
        let legacy = FakeKeychainStore(items: [TestStorageKey.session: session])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        #expect(try store.load(key: TestStorageKey.session) == session)
        #expect(modern.contents[TestStorageKey.session] == session)
        #expect(legacy.contents[TestStorageKey.session] == nil)
    }

    @Test("a save writes the data protection keychain and clears any legacy copy")
    func saveClearsLegacy() throws {
        let modern = FakeKeychainStore()
        let legacy = FakeKeychainStore(items: [TestStorageKey.session: Data(TestValue.outdated.utf8)])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        try store.save(key: TestStorageKey.session, data: session)
        #expect(modern.contents[TestStorageKey.session] == session)
        #expect(legacy.contents[TestStorageKey.session] == nil)
    }

    @Test("a delete clears both keychains, so signing out leaves nothing behind")
    func deleteClearsBoth() throws {
        let modern = FakeKeychainStore(items: [TestStorageKey.session: session])
        let legacy = FakeKeychainStore(items: [TestStorageKey.session: session])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        try store.delete(key: TestStorageKey.session)
        #expect(modern.contents.isEmpty)
        #expect(legacy.contents.isEmpty)
    }

    @Test("a build without the keychain entitlement keeps using the legacy keychain")
    func missingEntitlementFallsBack() throws {
        let modern = FakeKeychainStore(isMissingEntitlement: true)
        let legacy = FakeKeychainStore()
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        try store.save(key: TestStorageKey.session, data: session)
        #expect(legacy.contents[TestStorageKey.session] == session)
        #expect(try store.load(key: TestStorageKey.session) == session)
        try store.delete(key: TestStorageKey.session)
        #expect(legacy.contents.isEmpty)
    }

    @Test("an item already in the data protection keychain never touches the legacy one")
    func modernItemWins() throws {
        let modern = FakeKeychainStore(items: [TestStorageKey.session: session])
        let legacy = FakeKeychainStore(items: [TestStorageKey.session: Data("stale".utf8)])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        #expect(try store.load(key: TestStorageKey.session) == session)
    }

    @Test("eager migration moves every legacy item without a read, and is safe to repeat")
    func migrateAllMovesEverything() {
        let modern = FakeKeychainStore()
        let legacy = FakeKeychainStore(items: [TestStorageKey.storedSessions: session, TestStorageKey.legacySession: Data(TestValue.outdated.utf8)])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        #expect(store.migrateAll() == 2)
        #expect(store.migrateAll() == 0)

        #expect(modern.contents[TestStorageKey.storedSessions] == session)
        #expect(modern.contents[TestStorageKey.legacySession] == Data(TestValue.outdated.utf8))
        #expect(legacy.contents.isEmpty)
    }

    @Test("eager migration never overwrites a newer data protection item")
    func migrateAllKeepsNewerItem() {
        let newer = Data("newer".utf8)
        let modern = FakeKeychainStore(items: [TestStorageKey.storedSessions: newer])
        let legacy = FakeKeychainStore(items: [TestStorageKey.storedSessions: session])

        #expect(MacKeychainStore(modern: modern, legacy: legacy).migrateAll() == 0)

        #expect(modern.contents[TestStorageKey.storedSessions] == newer)
        #expect(legacy.contents.isEmpty)
    }

    @Test("eager migration in a build without the entitlement leaves the legacy items alone")
    func migrateAllWithoutEntitlement() {
        let legacy = FakeKeychainStore(items: [TestStorageKey.storedSessions: session])
        let store = MacKeychainStore(modern: FakeKeychainStore(isMissingEntitlement: true), legacy: legacy)

        #expect(store.migrateAll() == 0)
        #expect(legacy.contents[TestStorageKey.storedSessions] == session)
    }

    @Test("a legacy keychain that cannot be listed is not an error")
    func migrateAllWithUnreadableLegacy() {
        let store = MacKeychainStore(modern: FakeKeychainStore(), legacy: FakeKeychainStore(isMissingEntitlement: true))
        #expect(store.migrateAll() == 0)
    }
}
