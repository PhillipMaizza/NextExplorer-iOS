@testable import CoreModels
import Testing

@Suite("ConfirmPhase")
struct ConfirmPhaseTests {
    @Test
    func askingShowsTheConfirmation() {
        var phase = ConfirmPhase.idle
        phase.ask()
        #expect(phase == .confirming)
        #expect(phase.isConfirming)
        #expect(!phase.isRunning)
    }

    @Test
    func askingWhileItRunsNeverAsksAgain() {
        var phase = ConfirmPhase.running
        phase.ask()
        #expect(phase == .running)
    }

    @Test
    func cancellingDismissesTheConfirmationOnly() {
        var confirming = ConfirmPhase.confirming
        confirming.cancel()
        #expect(confirming == .idle)

        var running = ConfirmPhase.running
        running.cancel()
        #expect(running == .running)
    }
}
