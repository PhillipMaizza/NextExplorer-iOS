import Foundation
import Localization
import ShareUploads
import UniformTypeIdentifiers

/// Stages one shared item, reporting how far its file has been read and stopping the read when
/// the task is cancelled (closing the sheet must not leave a large video still being copied).
enum ProviderStager {
    /// Reads of one item report whole percents at most, so progress doesn't flood the store.
    fileprivate static let percentSteps = 100.0

    /// Stages `provider` into `batch`: its files (a Live Photo is two), or none for an item with no
    /// file (a link, text). Finder and Files items and Live Photos go through `SharedItemLoader`,
    /// which knows their quirks; everything else is read here so the read can report progress and
    /// be cancelled.
    static func stage(
        _ provider: NSItemProvider,
        in batch: UploadBatch,
        onFraction: @escaping @Sendable (Double) -> Void
    ) async throws -> [UploadBatch.StagedFile] {
        guard let type = SharedItemLoader.preferredType(registered: provider.registeredTypeIdentifiers) else { return [] }
        if isLivePhoto(provider) || type.conforms(to: .fileURL) {
            return try await SharedItemLoader.stageAll(provider, in: batch)
        }
        return try await [stageFile(provider, type: type, in: batch, onFraction: onFraction)]
    }

    /// A Live Photo stands for a still and its motion video.
    static func isLivePhoto(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.compactMap(UTType.init).contains { $0.conforms(to: .livePhoto) }
    }

    private static func stageFile(
        _ provider: NSItemProvider,
        type: UTType,
        in batch: UploadBatch,
        onFraction: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadBatch.StagedFile {
        let suggestedName = provider.suggestedName
        let load = CancellableLoad()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard load.install(continuation) else { return }
                let progress = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, error in
                    guard let url else {
                        load.finish(.failure(error ?? CocoaError(.fileReadUnknown)))
                        return
                    }
                    guard load.isActive else { return }
                    load.finish(Result {
                        let name = SharedItemLoader.fileName(fileURL: url, suggestedName: suggestedName, type: type)
                        let file = try batch.envelope(for: url, fileName: name)
                        guard load.isActive else {
                            file.removeEnvelope()
                            throw CancellationError()
                        }
                        return file
                    })
                }
                load.attach(progress) { fraction in
                    onFraction((fraction * percentSteps).rounded(.down) / percentSteps)
                }
            }
        } onCancel: {
            load.cancel()
        }
    }

    /// The name shown for an item that failed: the provider's own, else its position.
    static func displayName(of provider: NSItemProvider, index: Int) -> String {
        guard let name = provider.suggestedName, !name.isEmpty else {
            return L10n.ShareUpload.fallbackItemName(index + 1)
        }
        return name
    }

    /// `NSItemProvider` wraps what went wrong in its own error and keeps the real one underneath,
    /// so the cause is read from the innermost error that says something.
    static func cause(of error: any Error) -> ItemFailureCause {
        if ShareUploadError.isOutOfSpace(error) {
            return .notEnoughSpace
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: nsError.code) {
            case .fileReadNoSuchFile, .fileNoSuchFile, .fileReadNoPermission, .fileReadUnknown, .fileReadCorruptFile:
                return .cannotRead
            default: break
            }
        }
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else { return .other }
        return cause(of: underlying)
    }
}

/// One in flight `loadFileRepresentation`: resumes its continuation exactly once, whichever of
/// the completion handler and a cancellation comes first, and cancels the provider's `Progress`
/// so the copy itself stops.
private final class CancellableLoad: @unchecked Sendable {
    private enum Constants {
        static let noStep = -1.0
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

    func attach(_ progress: Progress, onFraction: @escaping @Sendable (Double) -> Void) {
        let shouldCancel = lock.withLock {
            self.progress = progress
            return isCancelled
        }
        if shouldCancel {
            progress.cancel()
            return
        }
        let observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            guard let self, shouldReport(progress.fractionCompleted) else { return }
            onFraction(progress.fractionCompleted)
        }
        lock.withLock { self.observation = observation }
    }

    private func shouldReport(_ fraction: Double) -> Bool {
        lock.withLock {
            let step = (fraction * ProviderStager.percentSteps).rounded(.down)
            guard step > lastStep else { return false }
            lastStep = step
            return true
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
        let (taken, activeProgress): (CheckedContinuation<UploadBatch.StagedFile, any Error>?, Progress?) = lock.withLock {
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
