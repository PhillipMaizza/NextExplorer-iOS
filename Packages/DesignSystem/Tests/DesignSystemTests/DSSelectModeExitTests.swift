@testable import DesignSystem
import Testing
import TestUtils

/// Leaving select mode in order: one exit at a time, and none once select mode ended another way.
@MainActor
struct DSSelectModeExitTests {
    @MainActor
    private final class Counter {
        var value = 0
    }

    @Test("A second call while one is under way is ignored, so a double tap ends select mode once")
    func aSecondCallIsIgnored() async {
        let gate = AsyncGate()
        let exit = DSSelectModeExit(waitForIndicators: { try? await gate.wait() })
        let finished = Counter()

        exit { finished.value += 1 }
        exit { finished.value += 1 }
        let pending = exit.pending
        gate.open()
        await pending?.value

        #expect(finished.value == 1)
        #expect(exit.pending == nil)
    }

    @Test("A cancelled exit never finishes, and the next one runs")
    func aCancelledExitNeverFinishes() async {
        let gate = AsyncGate()
        let exit = DSSelectModeExit(waitForIndicators: { try? await gate.wait() })
        let finished = Counter()

        exit { finished.value += 1 }
        let cancelled = exit.pending
        exit.cancel()
        await cancelled?.value
        #expect(finished.value == 0)

        exit { finished.value += 10 }
        let next = exit.pending
        gate.open()
        await next?.value
        #expect(finished.value == 10)
    }
}
