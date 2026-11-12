import Dependencies
@testable import FilesClient
import Foundation
import Testing
import TestUtils

struct PreviewDownloadCoordinatorTests {
    private let fileA = URL(fileURLWithPath: "/tmp/preview-cache/a/preview.pdf")
    private let fileB = URL(fileURLWithPath: "/tmp/preview-cache/b/preview.pdf")

    @Test
    func collapsesConcurrentCallsForTheSameFileIntoOneTransfer() async throws {
        let coordinator = PreviewDownloadCoordinator()
        let runs = LockIsolated(0)
        let target = fileA
        let gate = AsyncGate()
        let work: @Sendable () async throws -> URL = {
            runs.withValue { $0 += 1 }
            try await gate.wait()
            return target
        }

        let results = LockIsolated<[URL]>([])
        try await withMainSerialExecutor {
            let first = Task { try await coordinator.run(forFileAt: target, work) }
            let second = Task { try await coordinator.run(forFileAt: target, work) }
            await Task.yield()
            gate.open()
            let firstValue = try await first.value
            let secondValue = try await second.value
            results.setValue([firstValue, secondValue])
        }

        #expect(results.value == [target, target])
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
        let gate = AsyncGate()
        func work(returning url: URL) -> @Sendable () async throws -> URL {
            { @Sendable in
                runs.withValue { $0 += 1 }
                try await gate.wait()
                return url
            }
        }

        let outcome = LockIsolated<[URL]>([])
        try await withMainSerialExecutor { [fileA, fileB] in
            let a = Task { try await coordinator.run(forFileAt: fileA, work(returning: fileA)) }
            let b = Task { try await coordinator.run(forFileAt: fileB, work(returning: fileB)) }
            await Task.yield()
            gate.open()
            let aValue = try await a.value
            let bValue = try await b.value
            outcome.setValue([aValue, bValue])
        }

        #expect(outcome.value == [fileA, fileB])

        #expect(runs.value == 2)
    }

    @Test
    func aFailedTransferPropagatesToEveryWaiterAndDoesNotStickAround() async throws {
        let coordinator = PreviewDownloadCoordinator()
        let runs = LockIsolated(0)
        struct Boom: Error {}
        let gate = AsyncGate()
        let failing: @Sendable () async throws -> URL = {
            runs.withValue { $0 += 1 }
            try await gate.wait()
            throw Boom()
        }

        let outcomes = LockIsolated<[Result<URL, any Error>]>([])
        await withMainSerialExecutor { [fileA] in
            let first = Task { try await coordinator.run(forFileAt: fileA, failing) }
            let second = Task { try await coordinator.run(forFileAt: fileA, failing) }
            await Task.yield()
            gate.open()
            let firstOutcome = await first.result
            let secondOutcome = await second.result
            outcomes.setValue([firstOutcome, secondOutcome])
        }
        let firstResult = outcomes.value[0]
        let secondResult = outcomes.value[1]

        #expect(throws: Boom.self) { try firstResult.get() }
        #expect(throws: Boom.self) { try secondResult.get() }
        #expect(runs.value == 1)

        // A later call is a fresh attempt, not a cached failure.
        _ = try await coordinator.run(forFileAt: fileA) { fileA }
        #expect(runs.value == 1)
    }
}
