import ComposableArchitecture

/// Runs `operation` and forwards its progress to the store as `action`. Only the latest position
/// matters: a bar cannot show the ones it skipped. Returns once the last position has been sent.
func withProgressActions<Action: Sendable, Value>(
    send: Send<Action>,
    action: @escaping @Sendable (Double) -> Action,
    operation: (@escaping @Sendable (Double) -> Void) async throws -> Value
) async throws -> Value {
    let (progress, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
    return try await withThrowingTaskGroup(of: Void.self) { group in
        defer { continuation.finish() }
        group.addTask {
            for await fraction in progress {
                await send(action(fraction))
            }
        }
        let value = try await operation { continuation.yield($0) }
        continuation.finish()
        try await group.waitForAll()
        return value
    }
}
