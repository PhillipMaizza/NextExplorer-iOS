import Foundation
@testable import Keychain
import Security
import Testing

@Suite("Shared keychain group migration")
struct SharedGroupKeychainStoreTests {
    /// Two access groups in one fake keychain. A query with no group reads either and deletes both,
    /// like the real one.
    private final class FakeKeychain: @unchecked Sendable {
        let lock = NSLock()
        var groups: [String: [String: Data]] = ["shared": [:], "app": [:]]
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
            if group == "shared", keychain.sharedIsMissingEntitlement {
                throw KeychainError.unexpectedStatus(errSecMissingEntitlement)
            }
        }

        func save(key: String, data: Data) throws {
            try check()
            keychain.lock.withLock { keychain.groups[group ?? "app", default: [:]][key] = data }
        }

        func load(key: String) throws -> Data? {
            try check()
            return keychain.lock.withLock {
                if let group {
                    return keychain.groups[group]?[key]
                }
                return keychain.groups["shared"]?[key] ?? keychain.groups["app"]?[key]
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
            shared: GroupStore(keychain: keychain, group: "shared"),
            anyGroup: GroupStore(keychain: keychain, group: nil),
            previousGroup: GroupStore(keychain: keychain, group: "app")
        )
    }

    private let session = Data("session".utf8)

    @Test("a session saved by an older release moves to the shared group on first read")
    func oldItemMovesOnRead() throws {
        let keychain = FakeKeychain()
        keychain.groups["app"] = ["session": session]
        let store = makeStore(keychain)

        #expect(try store.load(key: "session") == session)
        #expect(keychain.contents("shared")["session"] == session)
        #expect(keychain.contents("app")["session"] == nil)
    }

    @Test("a save goes to the shared group and clears the old copy")
    func saveClearsOldCopy() throws {
        let keychain = FakeKeychain()
        keychain.groups["app"] = ["session": Data("old".utf8)]
        let store = makeStore(keychain)

        try store.save(key: "session", data: session)

        #expect(keychain.contents("shared")["session"] == session)
        #expect(keychain.contents("app")["session"] == nil)
        #expect(try store.load(key: "session") == session)
    }

    @Test("signing out deletes the item from every group")
    func deleteClearsBothGroups() throws {
        let keychain = FakeKeychain()
        keychain.groups = ["shared": ["session": session], "app": ["session": session]]

        try makeStore(keychain).delete(key: "session")

        #expect(keychain.contents("shared").isEmpty)
        #expect(keychain.contents("app").isEmpty)
    }

    @Test("a build without the sharing entitlement keeps using the app's own group")
    func missingEntitlementFallsBack() throws {
        let keychain = FakeKeychain()
        keychain.sharedIsMissingEntitlement = true
        let store = makeStore(keychain)

        try store.save(key: "session", data: session)

        #expect(keychain.contents("app")["session"] == session)
        #expect(try store.load(key: "session") == session)
    }
}
