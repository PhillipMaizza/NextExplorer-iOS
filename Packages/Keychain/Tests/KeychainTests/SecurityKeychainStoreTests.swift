import Foundation
@testable import Keychain
import Testing
import TestUtils

@Suite("Security keychain store")
struct SecurityKeychainStoreTests {
    private func makeStore() -> SecurityKeychainStore {
        SecurityKeychainStore(configuration: .unique())
    }

    @Test("allKeys lists every key saved under the service and no others")
    func allKeysListsServiceItems() throws {
        let store = makeStore()
        let other = makeStore()
        try store.save(key: Constants.secondKey, data: Constants.secondPayload)
        try store.save(key: Constants.firstKey, data: Constants.firstPayload)
        try other.save(key: Constants.otherKey, data: Constants.otherPayload)
        defer {
            try? store.delete(key: Constants.firstKey)
            try? store.delete(key: Constants.secondKey)
            try? other.delete(key: Constants.otherKey)
        }

        #expect(try store.allKeys().sorted() == [Constants.firstKey, Constants.secondKey])
        #expect(try other.allKeys() == [Constants.otherKey])
    }

    @Test("allKeys of a service that holds nothing is empty rather than an error")
    func allKeysEmptyService() throws {
        #expect(try makeStore().allKeys() == [])
    }

    @Test("a deleted key is no longer listed")
    func deletedKeyLeavesListing() throws {
        let store = makeStore()
        try store.save(key: Constants.firstKey, data: Constants.firstPayload)
        try store.save(key: Constants.secondKey, data: Constants.secondPayload)
        try store.delete(key: Constants.firstKey)
        defer { try? store.delete(key: Constants.secondKey) }

        #expect(try store.allKeys() == [Constants.secondKey])
    }
}

private enum Constants {
    static let firstKey = "first"
    static let secondKey = "second"
    static let otherKey = "other"
    static let firstPayload = Data("1".utf8)
    static let secondPayload = Data("2".utf8)
    static let otherPayload = Data("3".utf8)
}
