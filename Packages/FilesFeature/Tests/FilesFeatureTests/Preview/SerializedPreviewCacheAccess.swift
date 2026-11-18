import Testing

/// Serializes every suite that reads, writes, or clears the shared
/// `Library/Caches/PreviewCache` directory. `PreviewCacheStoreTests` deletes the whole tree
/// and asserts on its exact byte count; without coordination it races any concurrent
/// reader/writer (`ThumbnailCacheTests`, `PDFThumbnailCacheTests`, `PDFThumbnailStoreTests`).
/// Swift Testing's built-in `.serialized` only orders tests *within* one suite, so this
/// coordinates them all on one process-wide gate.
struct SerializedPreviewCacheAccess: SuiteTrait, TestScoping {
    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await Self.gate.wait()
        do {
            try await function()
            await Self.gate.signal()
        } catch {
            await Self.gate.signal()
            throw error
        }
    }

    private static let gate = AsyncGate()
}

/// A fair binary semaphore: FIFO waiters, so a queued suite runs next rather than starving.
private actor AsyncGate {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if !held {
            held = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            held = false
        }
    }
}
