import Foundation
@testable import Keychain
import Security
import Testing
import TestUtils

@Suite("Shared keychain group failures")
struct SharedGroupKeychainStoreFailureTests {
    private struct Stores {
        let shared: FakeKeychainStore
        let anyGroup: FakeKeychainStore
        let previous: FakeKeychainStore
        let store: SharedGroupKeychainStore
    }

    private let session = Data(TestStorageKey.session.utf8)
    private let outdated = Data(TestValue.outdated.utf8)

    private func makeStores(
        shared: FakeKeychainStore = FakeKeychainStore(),
        anyGroup: FakeKeychainStore = FakeKeychainStore(),
        previous: FakeKeychainStore = FakeKeychainStore()
    ) -> Stores {
        Stores(
            shared: shared,
            anyGroup: anyGroup,
            previous: previous,
            store: SharedGroupKeychainStore(shared: shared, anyGroup: anyGroup, previousGroup: previous)
        )
    }

    @Test("the keys listed are the shared group's, not the app's own group")
    func allKeysComesFromSharedGroup() throws {
        let stores = makeStores(
            shared: FakeKeychainStore(items: [Constants.secondKey: session, Constants.firstKey: session]),
            anyGroup: FakeKeychainStore(items: [Constants.otherKey: session]),
            previous: FakeKeychainStore(items: [Constants.otherKey: session])
        )
        #expect(try stores.store.allKeys() == [Constants.firstKey, Constants.secondKey])
    }

    @Test("a save that fails for another reason than the entitlement is thrown and keeps the old copy")
    func saveRethrowsOtherFailures() {
        let shared = FakeKeychainStore()
        shared.fail(.save, with: Constants.locked)
        let stores = makeStores(shared: shared, previous: FakeKeychainStore(items: [TestStorageKey.session: outdated]))

        #expect(throws: Constants.locked) {
            try stores.store.save(key: TestStorageKey.session, data: session)
        }
        #expect(stores.previous.contents[TestStorageKey.session] == outdated)
        #expect(stores.anyGroup.calls.isEmpty)
    }

    @Test("a read failure in the shared group is thrown without trying the other groups")
    func loadRethrowsOtherFailures() {
        let shared = FakeKeychainStore()
        shared.fail(.load, with: Constants.locked)
        let stores = makeStores(shared: shared, anyGroup: FakeKeychainStore(items: [TestStorageKey.session: session]))

        #expect(throws: Constants.locked) {
            _ = try stores.store.load(key: TestStorageKey.session)
        }
        #expect(stores.anyGroup.calls.isEmpty)
    }

    @Test("a failed move on read still returns the session and keeps the old copy for the next read")
    func failedMoveKeepsOldCopy() throws {
        let shared = FakeKeychainStore()
        shared.fail(.save, with: Constants.locked)
        let stores = makeStores(
            shared: shared,
            anyGroup: FakeKeychainStore(items: [TestStorageKey.session: session]),
            previous: FakeKeychainStore(items: [TestStorageKey.session: session])
        )

        #expect(try stores.store.load(key: TestStorageKey.session) == session)
        #expect(stores.previous.contents[TestStorageKey.session] == session)
        #expect(stores.shared.contents.isEmpty)
    }

    @Test("eager migration skips an item it cannot read and still moves the others")
    func migrateAllSkipsUnreadableItem() {
        let previous = FakeKeychainStore(items: [Constants.firstKey: session, Constants.secondKey: outdated])
        previous.fail(.load, key: Constants.firstKey, with: Constants.locked)
        let stores = makeStores(previous: previous)

        #expect(stores.store.migrateAll() == 1)
        #expect(stores.shared.contents == [Constants.secondKey: outdated])
        #expect(stores.previous.contents == [Constants.firstKey: session])
    }

    @Test("eager migration keeps the old copy of an item it fails to write and still moves the others")
    func migrateAllKeepsOldCopyOnWriteFailure() {
        let shared = FakeKeychainStore()
        shared.fail(.save, key: Constants.firstKey, with: Constants.locked)
        let stores = makeStores(
            shared: shared,
            previous: FakeKeychainStore(items: [Constants.firstKey: session, Constants.secondKey: outdated])
        )

        #expect(stores.store.migrateAll() == 1)
        #expect(stores.shared.contents == [Constants.secondKey: outdated])
        #expect(stores.previous.contents == [Constants.firstKey: session])
    }

    @Test("an app group that cannot be listed has nothing migrated")
    func migrateAllWithoutListing() {
        let previous = FakeKeychainStore(items: [Constants.firstKey: session])
        previous.fail(.allKeys, with: Constants.locked)
        let stores = makeStores(previous: previous)

        #expect(stores.store.migrateAll() == 0)
        #expect(stores.previous.contents == [Constants.firstKey: session])
        #expect(stores.shared.contents.isEmpty)
    }

    @Test("a store that cannot list its keys leaves a Mac migration with nothing to move")
    func defaultListingIsEmpty() {
        let legacy = KeyListingUnsupportedStore(items: [Constants.firstKey: session])
        let modern = FakeKeychainStore()

        #expect(MacKeychainStore(modern: modern, legacy: legacy).migrateAll() == 0)
        #expect(modern.contents.isEmpty)
    }
}

/// A store that keeps the protocol's default `allKeys`.
private struct KeyListingUnsupportedStore: KeychainStore {
    let items: [String: Data]

    func save(key _: String, data _: Data) throws {}

    func load(key: String) throws -> Data? {
        items[key]
    }

    func delete(key _: String) throws {}
}

private enum Constants {
    static let locked = KeychainError.unexpectedStatus(errSecInteractionNotAllowed)
    static let firstKey = "first"
    static let secondKey = "second"
    static let otherKey = "other"
}
