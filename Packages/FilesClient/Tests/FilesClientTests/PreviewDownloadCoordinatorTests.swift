import Dependencies
@testable import FilesClient
import Foundation
import Testing
import TestUtils

struct PreviewDownloadCoordinatorTests {
    private struct Boom: Error {}

    private let fileA = URL(fileURLWithPath: "/tmp/preview-cache/a/preview.pdf")
    private let fileB = URL(fileURLWithPath: "/tmp/preview-cache/b/preview.pdf")

    @Test
    func collapsesConcurrentCallsForTheSameFileIntoOneTransfer() async throws {
        let joined = AsyncGate()
        let coordinator = PreviewDownloadCoordinator(onJoin: { joined.open() })
        let runs = LockIsolated(0)
        let target = fileA
        let started = AsyncGate()
        let gate = AsyncGate()
        let work: @Sendable () async throws -> URL = {
            runs.withValue { $0 += 1 }
            started.open()
            try await gate.wait()
            return target
        }

        let first = Task { try await coordinator.run(forFileAt: target, work) }
        try await started.wait()
        let second = Task { try await coordinator.run(forFileAt: target, work) }
        try await joined.wait()
        gate.open()
        let firstValue = try await first.value
        let secondValue = try await second.value

        #expect(firstValue == fileA)
        #expect(secondValue == fileA)
        #expect(runs.value == 1)
    }

    @Test
    func runsAFreshTransferOnceThePreviousOneHasCompleted() async throws {
        let coordinator = PreviewDownloadCoordinator()
        let runs = LockIsolated(0)
        let target = fileA
        let work: @Sendable () async throws -> URL = {
            runs.withValue { $0 += 1 }
            return target
        }

        _ = try await coordinator.run(forFileAt: target, work)
        _ = try await coordinator.run(forFileAt: target, work)

        #expect(runs.value == 2)
    }

    @Test
    func keepsDistinctFilePathsIndependent() async throws {
        let coordinator = PreviewDownloadCoordinator()
        let runs = LockIsolated(0)
        let startedA = AsyncGate()
        let startedB = AsyncGate()
        let gateA = AsyncGate()
        let gateB = AsyncGate()
        func work(returning url: URL, started: AsyncGate, gate: AsyncGate) -> @Sendable () async throws -> URL {
            { @Sendable in
                runs.withValue { $0 += 1 }
                started.open()
                try await gate.wait()
                return url
            }
        }

        let workA = work(returning: fileA, started: startedA, gate: gateA)
        let workB = work(returning: fileB, started: startedB, gate: gateB)
        let a = Task { [fileA] in try await coordinator.run(forFileAt: fileA, workA) }
        let b = Task { [fileB] in try await coordinator.run(forFileAt: fileB, workB) }

        // Both transfers are in flight at the same time, so neither collapsed into the other.
        try await startedA.wait()
        try await startedB.wait()
        #expect(runs.value == 2)

        gateB.open()
        let bValue = try await b.value
        gateA.open()
        let aValue = try await a.value

        #expect(aValue == fileA)
        #expect(bValue == fileB)
        #expect(runs.value == 2)
    }

    @Test
    func aFailedTransferPropagatesToEveryWaiterAndDoesNotStickAround() async throws {
        let joined = AsyncGate()
        let coordinator = PreviewDownloadCoordinator(onJoin: { joined.open() })
        let runs = LockIsolated(0)
        let started = AsyncGate()
        let gate = AsyncGate()
        let failing: @Sendable () async throws -> URL = {
            runs.withValue { $0 += 1 }
            started.open()
            try await gate.wait()
            throw Boom()
        }

        let first = Task { [fileA] in try await coordinator.run(forFileAt: fileA, failing) }
        try await started.wait()
        let second = Task { [fileA] in try await coordinator.run(forFileAt: fileA, failing) }
        try await joined.wait()
        gate.open()
        let firstOutcome = await first.result
        let secondOutcome = await second.result

        #expect(throws: Boom.self) { try firstOutcome.get() }
        #expect(throws: Boom.self) { try secondOutcome.get() }
        #expect(runs.value == 1)

        // A later call is a fresh attempt, not a cached failure.
        let fileA = fileA
        let recovered = try await coordinator.run(forFileAt: fileA) {
            runs.withValue { $0 += 1 }
            return fileA
        }
        #expect(recovered == fileA)
        #expect(runs.value == 2)
    }
}
