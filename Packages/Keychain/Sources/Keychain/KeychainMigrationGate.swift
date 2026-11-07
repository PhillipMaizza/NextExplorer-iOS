import Foundation

/// Holds keychain reads back while the launch migrations run off the main thread, so no read ever
/// sees a half moved keychain. Nothing waits unless a migration was begun: the Share Extension and
/// tests never begin one.
public final class KeychainMigrationGate: @unchecked Sendable {
    public static let shared = KeychainMigrationGate()

    /// A migration that never finishes must not hang every read for good.
    public static let defaultMaxWait: TimeInterval = 10

    private let condition = NSCondition()
    private var isMigrating = false

    public init() {}

    public func begin() {
        condition.withLock { isMigrating = true }
    }

    public func finish() {
        condition.withLock {
            isMigrating = false
            condition.broadcast()
        }
    }

    public func waitUntilFinished(maxWait: TimeInterval = KeychainMigrationGate.defaultMaxWait) {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: maxWait)
        while isMigrating {
            guard condition.wait(until: deadline) else { return }
        }
    }
}
