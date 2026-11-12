import Synchronization

/// A latch a test holds closed to keep work in flight, then opens to let it finish.
public final class AsyncGate: Sendable {
    private struct State {
        var isOpen = false
        var nextID = 0
        var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// Returns once the gate opens, or throws `CancellationError` if the waiting task is cancelled first.
    public func wait() async throws {
        let id = state.withLock { state -> Int in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enum Outcome { case resume, cancel, park }
                let outcome = state.withLock { state -> Outcome in
                    if state.isOpen { return .resume }
                    if Task.isCancelled { return .cancel }
                    state.waiters[id] = continuation
                    return .park
                }
                switch outcome {
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                case .park: break
                }
            }
        } onCancel: {
            let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
            waiter?.resume(throwing: CancellationError())
        }
    }

    public func open() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
            state.isOpen = true
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }
}

/// Keeps work in flight until the task is cancelled. No timer is involved.
public func suspendUntilCancelled() async throws {
    for await _ in AsyncStream<Void> { _ in } {}
    try Task.checkCancellation()
}
