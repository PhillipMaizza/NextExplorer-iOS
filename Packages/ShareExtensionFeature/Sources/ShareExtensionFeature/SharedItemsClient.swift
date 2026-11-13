import CoreModels
import Dependencies
import DependenciesMacros
import Foundation
import Localization
import ShareUploads
import UniformTypeIdentifiers

/// Why one shared item could not be staged.
public enum ItemFailureCause: Hashable, Sendable {
    case cannotRead
    case notEnoughSpace
    /// A folder was shared: only files can be uploaded.
    case folder
    case other
}

/// One shared item that could not be prepared, named so the user knows which file to share again.
public struct ItemFailure: Equatable, Sendable, Identifiable {
    /// The item's position among everything shared.
    public let index: Int
    public let name: String
    public let cause: ItemFailureCause

    public var id: Int {
        index
    }

    public init(index: Int, name: String, cause: ItemFailureCause) {
        self.index = index
        self.name = name
        self.cause = cause
    }
}

/// How far a preparation pass has got: items finished, and how much of the one being read.
public struct PreparationProgress: Equatable, Sendable {
    public var completed = 0
    public var fraction = 0.0

    public init(completed: Int = 0, fraction: Double = 0) {
        self.completed = completed
        self.fraction = fraction
    }
}

/// What a preparation pass left behind: everything staged so far (earlier passes included) and
/// the items of this pass that failed.
public struct PreparationReport: Equatable, Sendable {
    public var stagedCount: Int
    public var failures: [ItemFailure]

    public init(stagedCount: Int, failures: [ItemFailure]) {
        self.stagedCount = stagedCount
        self.failures = failures
    }
}

/// The items another app shared, as the extension received them. The extension's view controller
/// supplies the live value around its `NSItemProvider`s.
///
/// Preparing, starting and discarding are separate so that one unreadable item does not cost the
/// ones that staged fine: the staged batch waits, uncommitted, while the user chooses to retry the
/// failures or upload the rest.
@DependencyClient
public struct SharedItemsClient: Sendable {
    public var count: @Sendable () -> Int = { 0 }
    /// How many of the items are Live Photos, which upload as the still and its motion video.
    public var livePhotoCount: @Sendable () -> Int = { 0 }
    /// Stages the items at `indexes` (all of them when `nil`) into the pending batch for
    /// `credentials`' server, creating it on the first pass. An item that can't be read is
    /// skipped and reported, never fatal. Throws only for the whole pass (cancellation, no batch
    /// folder), and a cancelled pass has already discarded the batch.
    public var prepare: @Sendable (
        _ credentials: SessionCredentials,
        _ destination: String,
        _ indexes: [Int]?,
        _ onProgress: @Sendable @escaping (PreparationProgress) -> Void
    ) async throws -> PreparationReport
    /// Hands the pending batch to the background uploader. Returns how many files went out.
    public var start: @Sendable () throws -> Int
    /// Drops the pending batch and everything staged for it. Once `start` has taken the batch there
    /// is nothing left to drop: the uploads belong to the system and closing never stops them.
    public var discard: @Sendable () -> Void
}

extension SharedItemsClient: TestDependencyKey {
    public static let testValue: SharedItemsClient = {
        var client = SharedItemsClient()
        client.livePhotoCount = { 0 }
        return client
    }()
}

public extension SharedItemsClient {
    /// Uploads `providers` through `BackgroundUploader.shared`. An item with no file (a link) is
    /// skipped quietly.
    static func live(
        providers: [NSItemProvider],
        requestNotificationPermission: @escaping @Sendable () async
            -> Void = { await UploadNotifications.requestPermission() }
    ) -> SharedItemsClient {
        let box = ProviderBox(providers: providers)
        let pending = PendingBatch()
        return SharedItemsClient(
            count: { box.providers.count },
            livePhotoCount: { box.providers.filter(ProviderStager.isLivePhoto).count },
            prepare: { credentials, destination, indexes, onProgress in
                // Quiet permission for the "upload finished" notification, asked before anything goes out.
                await requestNotificationPermission()
                let uploader = BackgroundUploader.shared
                var batch = try pending.batch ?? uploader.makeBatch(credentials: credentials, destination: destination)
                pending.batch = batch
                let targets = indexes ?? Array(box.providers.indices)
                var failures: [ItemFailure] = []
                do {
                    for (position, index) in targets.enumerated() where box.providers.indices.contains(index) {
                        try Task.checkCancellation()
                        onProgress(PreparationProgress(completed: position))
                        let provider = box.providers[index]
                        do {
                            let staged = try await SharedItemLoader.stageAll(provider, in: batch) { fraction in
                                onProgress(PreparationProgress(completed: position, fraction: fraction))
                            }
                            for file in staged {
                                batch.add(file)
                            }
                            pending.batch = batch
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            try Task.checkCancellation()
                            failures.append(ItemFailure(
                                index: index,
                                name: ProviderStager.displayName(of: provider, index: index),
                                cause: ProviderStager.cause(of: error)
                            ))
                        }
                    }
                    onProgress(PreparationProgress(completed: targets.count))
                    return PreparationReport(stagedCount: batch.count, failures: failures)
                } catch {
                    uploader.discard(batch)
                    pending.batch = nil
                    throw error
                }
            },
            start: {
                guard let batch = pending.take() else { throw CocoaError(.fileNoSuchFile) }
                do {
                    try BackgroundUploader.shared.start(batch)
                } catch {
                    BackgroundUploader.shared.discard(batch)
                    throw error
                }
                return batch.count
            },
            discard: {
                guard let batch = pending.take() else { return }
                BackgroundUploader.shared.discard(batch)
            }
        )
    }
}

/// `NSItemProvider` is thread safe for loading but not marked `Sendable`.
private final class ProviderBox: @unchecked Sendable {
    let providers: [NSItemProvider]

    init(providers: [NSItemProvider]) {
        self.providers = providers
    }
}

/// The batch being staged, shared between a preparation pass and the actions that start or drop it.
final class PendingBatch: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: UploadBatch?

    var batch: UploadBatch? {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    /// Hands the batch to exactly one caller, so a start and a discard can never both act on it.
    func take() -> UploadBatch? {
        lock.withLock {
            defer { storage = nil }
            return storage
        }
    }
}

public extension DependencyValues {
    var sharedItems: SharedItemsClient {
        get { self[SharedItemsClient.self] }
        set { self[SharedItemsClient.self] = newValue }
    }
}
