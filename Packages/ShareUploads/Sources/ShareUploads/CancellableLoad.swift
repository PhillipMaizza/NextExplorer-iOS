import Foundation

/// One in flight `loadFileRepresentation`: resumes its continuation exactly once, whichever of
/// the completion handler and a cancellation comes first, and cancels the provider's `Progress`
/// so the copy itself stops. Progress is reported in whole percents at most, so it doesn't flood
/// the store.
final class CancellableLoad: @unchecked Sendable {
    private enum Constants {
        static let noStep = -1.0
        static let percentSteps = 100.0
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<UploadBatch.StagedFile, any Error>?
    private var progress: Progress?
    private var observation: NSKeyValueObservation?
    private var isCancelled = false
    private var isFinished = false
    private var lastStep = Constants.noStep

    /// Whether the result is still wanted (not finished, not cancelled).
    var isActive: Bool {
        lock.withLock { !isFinished && !isCancelled }
    }

    /// `false` when the task was already cancelled: the continuation was resumed and nothing may start.
    func install(_ continuation: CheckedContinuation<UploadBatch.StagedFile, any Error>) -> Bool {
        let alreadyCancelled = lock.withLock {
            if isCancelled {
                isFinished = true
                return true
            }
            self.continuation = continuation
            return false
        }
        if alreadyCancelled {
            continuation.resume(throwing: CancellationError())
        }
        return !alreadyCancelled
    }

    func attach(_ progress: Progress?, onFraction: @escaping @Sendable (Double) -> Void) {
        guard let progress else { return }
        let shouldCancel = lock.withLock {
            self.progress = progress
            return isCancelled
        }
        if shouldCancel {
            progress.cancel()
            return
        }
        // `.initial`: whatever was read before this observer existed is reported too.
        let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            guard let self, let step = nextStep(for: progress.fractionCompleted) else { return }
            onFraction(step / Constants.percentSteps)
        }
        lock.withLock { self.observation = observation }
    }

    /// The new whole percent, or `nil` when it did not move.
    private func nextStep(for fraction: Double) -> Double? {
        lock.withLock {
            let step = (fraction * Constants.percentSteps).rounded(.down)
            guard step > lastStep else { return nil }
            lastStep = step
            return step
        }
    }

    func finish(_ result: Result<UploadBatch.StagedFile, any Error>) {
        let taken: CheckedContinuation<UploadBatch.StagedFile, any Error>? = lock.withLock {
            isFinished = true
            observation = nil
            defer { continuation = nil }
            return continuation
        }
        taken?.resume(with: result)
    }

    func cancel() {
        let (taken, activeProgress): (CheckedContinuation<UploadBatch.StagedFile, any Error>?, Progress?) = lock
            .withLock {
                isCancelled = true
                isFinished = true
                observation = nil
                defer { continuation = nil }
                return (continuation, progress)
            }
        activeProgress?.cancel()
        taken?.resume(throwing: CancellationError())
    }
}
