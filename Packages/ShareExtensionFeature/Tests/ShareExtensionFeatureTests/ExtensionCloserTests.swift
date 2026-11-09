@testable import ShareExtensionFeature
import Testing

@MainActor
struct ExtensionCloserTests {
    private final class Calls {
        var completed = 0
        var cancelled = 0
    }

    private func closer(_ calls: Calls) -> ExtensionCloser {
        ExtensionCloser(complete: { calls.completed += 1 }, cancel: { calls.cancelled += 1 })
    }

    @Test("Closing twice completes the request once: the system rejects a second call")
    func completesOnce() {
        let calls = Calls()
        let closer = closer(calls)
        closer.close(completed: true)
        closer.close(completed: true)
        closer.close(completed: false)
        #expect(calls.completed == 1)
        #expect(calls.cancelled == 0)
    }

    @Test("Whichever close comes first wins, a cancel included")
    func firstCloseWins() {
        let calls = Calls()
        let closer = closer(calls)
        closer.close(completed: false)
        closer.close(completed: true)
        #expect(calls.cancelled == 1)
        #expect(calls.completed == 0)
    }
}
