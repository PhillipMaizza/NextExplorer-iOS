import Foundation
@testable import Keychain
import Security

/// An in memory keychain. `isMissingEntitlement` makes every call fail as an unsigned build's data
/// protection keychain does; `failures` makes one operation fail for every key, or for one key only.
final class FakeKeychainStore: KeychainStore, @unchecked Sendable {
    enum Operation: Hashable, Sendable {
        case save, load, delete, allKeys
    }

    private let lock = NSLock()
    private var items: [String: Data]
    private var failures: [Failure: KeychainError] = [:]
    private var recordedCalls: [String] = []
    let isMissingEntitlement: Bool

    private struct Failure: Hashable {
        let operation: Operation
        /// `nil`: every key.
        let key: String?
    }

    init(items: [String: Data] = [:], isMissingEntitlement: Bool = false) {
        self.items = items
        self.isMissingEntitlement = isMissingEntitlement
    }

    var contents: [String: Data] {
        lock.withLock { items }
    }

    /// Every call made so far as "operation key", in order.
    var calls: [String] {
        lock.withLock { recordedCalls }
    }

    func fail(_ operation: Operation, key: String? = nil, with error: KeychainError) {
        lock.withLock { failures[Failure(operation: operation, key: key)] = error }
    }

    private func check(_ operation: Operation, key: String?) throws {
        lock.withLock { recordedCalls.append("\(operation) \(key ?? "")") }
        if isMissingEntitlement {
            throw KeychainError.unexpectedStatus(errSecMissingEntitlement)
        }
        let error = lock.withLock { failures[Failure(operation: operation, key: key)] ?? failures[Failure(
            operation: operation,
            key: nil
        )] }
        if let error {
            throw error
        }
    }

    func save(key: String, data: Data) throws {
        try check(.save, key: key)
        lock.withLock { items[key] = data }
    }

    func load(key: String) throws -> Data? {
        try check(.load, key: key)
        return lock.withLock { items[key] }
    }

    func delete(key: String) throws {
        try check(.delete, key: key)
        lock.withLock { items[key] = nil }
    }

    func allKeys() throws -> [String] {
        try check(.allKeys, key: nil)
        return lock.withLock { Array(items.keys).sorted() }
    }
}
