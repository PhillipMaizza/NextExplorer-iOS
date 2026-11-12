import Foundation

/// Minimal lock box so the progress callback (invoked on the URLSession delegate queue) can collect
/// values across threads in the test.
final class LockIsolatedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func withValue(_ mutate: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        mutate(&stored)
    }
}
