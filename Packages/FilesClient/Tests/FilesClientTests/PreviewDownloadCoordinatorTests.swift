import Dependencies
import Foundation
import Testing

@testable import FilesClient

@Suite
struct PreviewDownloadCoordinatorTests {
    private let fileA = URL(fileURLWithPath: "/tmp/preview-cache/a/preview.pdf")
    private let fileB = URL(fileURLWithPath: "/tmp/preview-cache/b/preview.pdf")

    @Test
    func collapsesConcurrentCallsForTheSameFileIntoOneTransfer() async throws {
        let coordinator = PreviewDownloadCoordinator()
        let runs = LockIsolated(0)
        let target = fileA
        let work: @Sendable () async throws -> URL = {
            runs.withValue { $0 += 1 }
            try await Task.sleep(for: .milliseconds(50))
            return target
        }

        async let first = coordinator.run(forFileAt: target, work)
        async let second = coordinator.run(forFileAt: target, work)
        let results = try await [first, second]

        #expect(results == [target, target])
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
        func work(returning url: URL) -> @Sendable () async throws -> URL {
            { @Sendable in
                runs.withValue { $0 += 1 }
                try await Task.sleep(for: .milliseconds(20))
                return url
            }
        }

        async let a = coordinator.run(forFileAt: fileA, work(returning: fileA))
        async let b = coordinator.run(forFileAt: fileB, work(returning: fileB))
        _ = try await [a, b]

        #expect(runs.value == 2)
    }

    @Test
    func aFailedTransferPropagatesToEveryWaiterAndDoesNotStickAround() async throws {
        let coordinator = PreviewDownloadCoordinator()
        let runs = LockIsolated(0)
        struct Boom: Error {}
        let failing: @Sendable () async throws -> URL = {
            runs.withValue { $0 += 1 }
            try await Task.sleep(for: .milliseconds(20))
            throw Boom()
        }

        let first = Task { try await coordinator.run(forFileAt: fileA, failing) }
        let second = Task { try await coordinator.run(forFileAt: fileA, failing) }
        let firstResult = await first.result
        let secondResult = await second.result

        #expect(throws: Boom.self) { try firstResult.get() }
        #expect(throws: Boom.self) { try secondResult.get() }
        #expect(runs.value == 1)

        // A later call is a fresh attempt, not a cached failure.
        _ = try await coordinator.run(forFileAt: fileA) { self.fileA }
        #expect(runs.value == 1)
    }
}
