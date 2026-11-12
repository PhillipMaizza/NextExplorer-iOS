import Foundation

final class LockIsolated<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func withValue(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }
}
