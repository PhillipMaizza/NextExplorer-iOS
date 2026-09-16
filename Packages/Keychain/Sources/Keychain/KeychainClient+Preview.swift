import Foundation

public extension KeychainClient {
    static func inMemory() -> KeychainClient {
        let storage = LockedStorage()
        return KeychainClient(
            save: { storage.set($1, forKey: $0) },
            load: { storage.value(forKey: $0) },
            delete: { storage.removeValue(forKey: $0) }
        )
    }

    static let previewValue: KeychainClient = .inMemory()
}

/// `@unchecked Sendable` is safe here: every access to `storage` is behind `lock`, so the
/// compiler just can't see the synchronization NSLock actually provides.
private final class LockedStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func set(_ data: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = data
    }

    func value(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func removeValue(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
