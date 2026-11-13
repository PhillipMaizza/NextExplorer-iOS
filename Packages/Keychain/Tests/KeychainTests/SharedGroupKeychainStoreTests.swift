import Foundation
@testable import Keychain
import Security
import Testing
import TestUtils

@Suite("Shared keychain group migration")
struct SharedGroupKeychainStoreTests {
    /// Two access groups in one fake keychain. A query with no group reads either and deletes both,
    /// like the real one.
    private final class FakeKeychain: @unchecked Sendable {
        let lock = NSLock()
        var groups: [String: [String: Data]] = [Constants.sharedGroup: [:], Constants.appGroup: [:]]
        var sharedIsMissingEntitlement = false

        func contents(_ group: String) -> [String: Data] {
            lock.withLock { groups[group] ?? [:] }
        }
    }

    private struct GroupStore: KeychainStore {
        let keychain: FakeKeychain
        /// `nil`: no access group in the query.
        let group: String?

        private func check() throws {
            if group == Constants.sharedGroup, keychain.sharedIsMissingEntitlement {
                throw KeychainError.unexpectedStatus(errSecMissingEntitlement)
            }
        }

        func save(key: String, data: Data) throws {
            try check()
            keychain.lock.withLock { keychain.groups[group ?? Constants.appGroup, default: [:]][key] = data }
        }

        func load(key: String) throws -> Data? {
            try check()
            return keychain.lock.withLock {
                if let group {
                    return keychain.groups[group]?[key]
                }
                return keychain.groups[Constants.sharedGroup]?[key] ?? keychain.groups[Constants.appGroup]?[key]
            }
        }

        func allKeys() throws -> [String] {
            try check()
            return keychain.lock.withLock {
                guard let group else { return [] }
                return keychain.groups[group].map { Array($0.keys).sorted() } ?? []
            }
        }

        func delete(key: String) throws {
            try check()
            keychain.lock.withLock {
                if let group {
                    keychain.groups[group]?[key] = nil
                } else {
                    for name in keychain.groups.keys {
                        keychain.groups[name]?[key] = nil
                    }
                }
            }
        }
    }

    private func makeStore(_ keychain: FakeKeychain) -> SharedGroupKeychainStore {
        SharedGroupKeychainStore(
            shared: GroupStore(keychain: keychain, group: Constants.sharedGroup),
            anyGroup: GroupStore(keychain: keychain, group: nil),
            previousGroup: GroupStore(keychain: keychain, group: Constants.appGroup)
        )
    }

    private let session = Data(TestStorageKey.session.utf8)

    @Test("a session saved by an older release moves to the shared group on first read")
    func oldItemMovesOnRead() throws {
        let keychain = FakeKeychain()
        keychain.groups[Constants.appGroup] = [TestStorageKey.session: session]
        let store = makeStore(keychain)

        #expect(try store.load(key: TestStorageKey.session) == session)
        #expect(keychain.contents(Constants.sharedGroup)[TestStorageKey.session] == session)
        #expect(keychain.contents(Constants.appGroup)[TestStorageKey.session] == nil)
    }

    @Test("a save goes to the shared group and clears the old copy")
    func saveClearsOldCopy() throws {
        let keychain = FakeKeychain()
        keychain.groups[Constants.appGroup] = [TestStorageKey.session: Data(TestValue.outdated.utf8)]
        let store = makeStore(keychain)

        try store.save(key: TestStorageKey.session, data: session)

        #expect(keychain.contents(Constants.sharedGroup)[TestStorageKey.session] == session)
        #expect(keychain.contents(Constants.appGroup)[TestStorageKey.session] == nil)
        #expect(try store.load(key: TestStorageKey.session) == session)
    }

    @Test("signing out deletes the item from every group")
    func deleteClearsBothGroups() throws {
        let keychain = FakeKeychain()
        keychain.groups = [
            Constants.sharedGroup: [TestStorageKey.session: session],
            Constants.appGroup: [TestStorageKey.session: session],
        ]

        try makeStore(keychain).delete(key: TestStorageKey.session)

        #expect(keychain.contents(Constants.sharedGroup).isEmpty)
        #expect(keychain.contents(Constants.appGroup).isEmpty)
    }

    @Test("a build without the sharing entitlement keeps using the app's own group")
    func missingEntitlementFallsBack() throws {
        let keychain = FakeKeychain()
        keychain.sharedIsMissingEntitlement = true
        let store = makeStore(keychain)

        try store.save(key: TestStorageKey.session, data: session)

        #expect(keychain.contents(Constants.appGroup)[TestStorageKey.session] == session)
        #expect(try store.load(key: TestStorageKey.session) == session)
    }

    @Test("eager migration moves every item from the app's group without a read")
    func migrateAllMovesEverything() {
        let keychain = FakeKeychain()
        keychain.groups[Constants.appGroup] = [
            TestStorageKey.storedSessions: session,
            "certificate.index": Data("index".utf8),
        ]
        let store = makeStore(keychain)

        #expect(store.migrateAll() == 2)

        #expect(keychain.contents(Constants.sharedGroup)[TestStorageKey.storedSessions] == session)
        #expect(keychain.contents(Constants.sharedGroup)["certificate.index"] == Data("index".utf8))
        #expect(keychain.contents(Constants.appGroup).isEmpty)
    }

    @Test("eager migration never overwrites a newer item in the shared group")
    func migrateAllKeepsNewerSharedItem() {
        let keychain = FakeKeychain()
        let newer = Data("newer".utf8)
        keychain.groups = [
            Constants.sharedGroup: [TestStorageKey.storedSessions: newer],
            Constants.appGroup: [TestStorageKey.storedSessions: session],
        ]

        #expect(makeStore(keychain).migrateAll() == 0)

        #expect(keychain.contents(Constants.sharedGroup)[TestStorageKey.storedSessions] == newer)
        #expect(
            keychain.contents(Constants.appGroup).isEmpty,
            "the stale copy goes so only one credential copy remains"
        )
    }

    @Test("eager migration is a no-op when nothing is left, and safe to repeat")
    func migrateAllIsIdempotent() {
        let keychain = FakeKeychain()
        keychain.groups[Constants.appGroup] = [TestStorageKey.storedSessions: session]
        let store = makeStore(keychain)

        #expect(store.migrateAll() == 1)
        #expect(store.migrateAll() == 0)
        #expect(keychain.contents(Constants.sharedGroup)[TestStorageKey.storedSessions] == session)
    }

    @Test("eager migration leaves items alone in a build without the sharing entitlement")
    func migrateAllWithoutEntitlement() {
        let keychain = FakeKeychain()
        keychain.sharedIsMissingEntitlement = true
        keychain.groups[Constants.appGroup] = [TestStorageKey.storedSessions: session]

        #expect(makeStore(keychain).migrateAll() == 0)

        #expect(keychain.contents(Constants.appGroup)[TestStorageKey.storedSessions] == session)
    }

    @Test("eager migration without a known previous group does nothing")
    func migrateAllWithoutPreviousGroup() {
        let keychain = FakeKeychain()
        keychain.groups[Constants.appGroup] = [TestStorageKey.storedSessions: session]
        let store = SharedGroupKeychainStore(
            shared: GroupStore(keychain: keychain, group: Constants.sharedGroup),
            anyGroup: GroupStore(keychain: keychain, group: nil),
            previousGroup: nil
        )

        #expect(store.migrateAll() == 0)
        #expect(keychain.contents(Constants.appGroup)[TestStorageKey.storedSessions] == session)
    }

    @Test("the launch hook does nothing in a build without the sharing entitlement")
    func launchHookIsANoOpWithoutSharing() {
        #expect(KeychainClient.migrateToSharedGroupIfNeeded() == 0)
    }
}

private enum Constants {
    static let appGroup = "app"
    static let sharedGroup = "shared"
}
