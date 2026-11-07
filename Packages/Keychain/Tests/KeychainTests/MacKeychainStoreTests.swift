import Foundation
@testable import Keychain
import Security
import Testing

@Suite("Mac keychain migration")
struct MacKeychainStoreTests {
    /// An in memory keychain; `isMissingEntitlement` makes every call fail as an unsigned build's
    /// data protection keychain does.
    private final class FakeStore: KeychainStore, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: Data] = [:]
        let isMissingEntitlement: Bool

        init(items: [String: Data] = [:], isMissingEntitlement: Bool = false) {
            self.items = items
            self.isMissingEntitlement = isMissingEntitlement
        }

        var contents: [String: Data] {
            lock.withLock { items }
        }

        private func check() throws {
            if isMissingEntitlement {
                throw KeychainError.unexpectedStatus(errSecMissingEntitlement)
            }
        }

        func save(key: String, data: Data) throws {
            try check()
            lock.withLock { items[key] = data }
        }

        func load(key: String) throws -> Data? {
            try check()
            return lock.withLock { items[key] }
        }

        func delete(key: String) throws {
            try check()
            lock.withLock { items[key] = nil }
        }

        func allKeys() throws -> [String] {
            try check()
            return lock.withLock { Array(items.keys) }
        }
    }

    private let session = Data("session".utf8)

    @Test("a session from the legacy keychain moves to the data protection keychain on first read")
    func legacyItemMovesOnRead() throws {
        let modern = FakeStore()
        let legacy = FakeStore(items: ["session": session])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        #expect(try store.load(key: "session") == session)
        #expect(modern.contents["session"] == session)
        #expect(legacy.contents["session"] == nil)
    }

    @Test("a save writes the data protection keychain and clears any legacy copy")
    func saveClearsLegacy() throws {
        let modern = FakeStore()
        let legacy = FakeStore(items: ["session": Data("old".utf8)])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        try store.save(key: "session", data: session)
        #expect(modern.contents["session"] == session)
        #expect(legacy.contents["session"] == nil)
    }

    @Test("a delete clears both keychains, so signing out leaves nothing behind")
    func deleteClearsBoth() throws {
        let modern = FakeStore(items: ["session": session])
        let legacy = FakeStore(items: ["session": session])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        try store.delete(key: "session")
        #expect(modern.contents.isEmpty)
        #expect(legacy.contents.isEmpty)
    }

    @Test("a build without the keychain entitlement keeps using the legacy keychain")
    func missingEntitlementFallsBack() throws {
        let modern = FakeStore(isMissingEntitlement: true)
        let legacy = FakeStore()
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        try store.save(key: "session", data: session)
        #expect(legacy.contents["session"] == session)
        #expect(try store.load(key: "session") == session)
        try store.delete(key: "session")
        #expect(legacy.contents.isEmpty)
    }

    @Test("an item already in the data protection keychain never touches the legacy one")
    func modernItemWins() throws {
        let modern = FakeStore(items: ["session": session])
        let legacy = FakeStore(items: ["session": Data("stale".utf8)])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        #expect(try store.load(key: "session") == session)
    }

    @Test("eager migration moves every legacy item without a read, and is safe to repeat")
    func migrateAllMovesEverything() {
        let modern = FakeStore()
        let legacy = FakeStore(items: ["storedSessions": session, "currentSession": Data("old".utf8)])
        let store = MacKeychainStore(modern: modern, legacy: legacy)

        #expect(store.migrateAll() == 2)
        #expect(store.migrateAll() == 0)

        #expect(modern.contents["storedSessions"] == session)
        #expect(modern.contents["currentSession"] == Data("old".utf8))
        #expect(legacy.contents.isEmpty)
    }

    @Test("eager migration never overwrites a newer data protection item")
    func migrateAllKeepsNewerItem() {
        let newer = Data("newer".utf8)
        let modern = FakeStore(items: ["storedSessions": newer])
        let legacy = FakeStore(items: ["storedSessions": session])

        #expect(MacKeychainStore(modern: modern, legacy: legacy).migrateAll() == 0)

        #expect(modern.contents["storedSessions"] == newer)
        #expect(legacy.contents.isEmpty)
    }

    @Test("eager migration in a build without the entitlement leaves the legacy items alone")
    func migrateAllWithoutEntitlement() {
        let legacy = FakeStore(items: ["storedSessions": session])
        let store = MacKeychainStore(modern: FakeStore(isMissingEntitlement: true), legacy: legacy)

        #expect(store.migrateAll() == 0)
        #expect(legacy.contents["storedSessions"] == session)
    }

    @Test("a legacy keychain that cannot be listed is not an error")
    func migrateAllWithUnreadableLegacy() {
        let store = MacKeychainStore(modern: FakeStore(), legacy: FakeStore(isMissingEntitlement: true))
        #expect(store.migrateAll() == 0)
    }
}
