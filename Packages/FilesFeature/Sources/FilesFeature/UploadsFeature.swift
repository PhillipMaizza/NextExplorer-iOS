import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

/// The app-wide upload queue. Owned by `MainTabFeature` so its state and effects outlive any
/// folder screen or tab switch. Files upload one at a time (sequential, matching
/// `BrowseFeature.startBulkDownload`); each job targets the folder it was started from. When
/// the queue drains, the parent is told which folders changed so it can refetch just those.
@Reducer
public struct UploadsFeature {
    public struct UploadJob: Equatable, Sendable, Identifiable {
        public enum Status: Equatable, Sendable {
            case queued, uploading, completed, failed(String)

            var isTerminal: Bool {
                switch self {
                case .completed, .failed: true
                case .queued, .uploading: false
                }
            }

            var isFailed: Bool {
                if case .failed = self { true } else { false }
            }
        }

        public let id: UUID
        public let fileURL: URL
        public let fileName: String
        public let destination: String
        public var progress: Double
        public var status: Status
    }

    /// Reported to the parent when the queue drains: what to toast, and which folders to
    /// refetch (`changedPaths` is deduplicated destinations of everything that succeeded).
    public struct FinishSummary: Equatable, Sendable {
        public var uploadedCount: Int
        public var failedCount: Int
        public var lastDestination: String?
        public var changedPaths: Set<String>
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        public var jobs: IdentifiedArrayOf<UploadJob> = []
        public var isSheetPresented = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        /// Anything still queued or uploading.
        public var isActive: Bool {
            jobs.contains { !$0.status.isTerminal }
        }

        public var failedCount: Int {
            jobs.filter { $0.status.isFailed }.count
        }

        /// The bar stays up while uploads run *and* while failures are waiting to be retried
        /// or dismissed.
        public var isBarVisible: Bool { isActive || failedCount > 0 }

        var currentJob: UploadJob? {
            jobs.first { $0.status == .uploading }
        }

        var completedCount: Int {
            jobs.filter { $0.status == .completed }.count
        }

        var hasClearableJobs: Bool {
            jobs.contains { $0.status.isTerminal }
        }

        /// Files still waiting or in flight — the only count the bar shows, so it stays honest
        /// even when a second batch is enqueued before the first drains.
        var remainingCount: Int {
            jobs.filter { !$0.status.isTerminal }.count
        }
    }

    public enum Action: Equatable, Sendable {
        case enqueue([PendingUpload])
        /// The app returned to the foreground. A default `URLSession` upload that lost its
        /// connection while the app was suspended has already surfaced as `.failed`; those are
        /// requeued. Jobs still genuinely `.uploading` are left alone to resume or time out on
        /// their own — restarting them from zero would nuke healthy transfers and, on an
        /// ambiguous completion, duplicate the file on the server (the backend has no
        /// idempotency key to lean on).
        case appResumed
        case startNextIfIdle
        case progress(id: UUID, Double)
        case uploadResponse(id: UUID, Result<FileItem, FilesClientError>)
        case cancelJobTapped(id: UUID)
        case cancelAllTapped
        case retryTapped(id: UUID)
        case retryAllFailedTapped
        case clearFinishedTapped
        case sheetPresented(Bool)
        case barTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case queueFinished(FinishSummary)
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.uploadStaging) var uploadStaging
    private enum CancelID: Hashable { case job(UUID) }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .enqueue(pending):
                guard !pending.isEmpty else { return .none }
                // A fresh batch starts from a clean slate so finished rows don't pile up.
                if !state.isActive {
                    state.jobs.removeAll { $0.status.isTerminal }
                }
                for item in pending {
                    state.jobs.append(UploadJob(
                        id: item.id, fileURL: item.fileURL, fileName: item.fileName,
                        destination: item.destination, progress: 0, status: .queued
                    ))
                }
                return .send(.startNextIfIdle)

            case .appResumed:
                let stalled = state.jobs.filter { $0.status.isFailed }
                guard !stalled.isEmpty else { return .none }
                for job in stalled {
                    state.jobs[id: job.id]?.status = .queued
                    state.jobs[id: job.id]?.progress = 0
                }
                return .send(.startNextIfIdle)

            case .startNextIfIdle:
                guard state.currentJob == nil,
                      let next = state.jobs.first(where: { $0.status == .queued })
                else { return .none }
                state.jobs[id: next.id]?.status = .uploading
                state.jobs[id: next.id]?.progress = 0
                return upload(next, serverURL: state.serverURL)

            case let .progress(id, value):
                state.jobs[id: id]?.progress = value
                return .none

            case let .uploadResponse(id, result):
                guard let job = state.jobs[id: id] else { return .none }
                var discardEffect: Effect<Action> = .none
                switch result {
                case .success:
                    state.jobs[id: id]?.status = .completed
                    state.jobs[id: id]?.progress = 1
                    discardEffect = discard([job.fileURL])
                case let .failure(error):
                    state.jobs[id: id]?.status = .failed(Self.message(for: error))
                }

                if state.jobs.contains(where: { $0.status == .queued }) {
                    return .merge(discardEffect, .send(.startNextIfIdle))
                }
                return .merge(discardEffect, .send(.delegate(.queueFinished(state.finishSummary))))

            case let .cancelJobTapped(id):
                let stagedURL = state.jobs[id: id]?.fileURL
                state.jobs.remove(id: id)
                if state.jobs.isEmpty { state.isSheetPresented = false }
                return .merge(
                    .cancel(id: CancelID.job(id)),
                    discard(stagedURL.map { [$0] } ?? []),
                    .send(.startNextIfIdle)
                )

            case .cancelAllTapped:
                let stagedURLs = state.jobs.map(\.fileURL)
                let cancels = state.jobs.map { Effect<Action>.cancel(id: CancelID.job($0.id)) }
                state.jobs.removeAll()
                state.isSheetPresented = false
                return .merge(cancels + [discard(stagedURLs)])

            case let .retryTapped(id):
                guard case .failed = state.jobs[id: id]?.status else { return .none }
                state.jobs[id: id]?.status = .queued
                state.jobs[id: id]?.progress = 0
                return .send(.startNextIfIdle)

            case .retryAllFailedTapped:
                let failed = state.jobs.filter { $0.status.isFailed }
                guard !failed.isEmpty else { return .none }
                for job in failed {
                    state.jobs[id: job.id]?.status = .queued
                    state.jobs[id: job.id]?.progress = 0
                }
                return .send(.startNextIfIdle)

            case .clearFinishedTapped:
                let stagedURLs = state.jobs.filter { $0.status.isTerminal }.map(\.fileURL)
                state.jobs.removeAll { $0.status.isTerminal }
                if state.jobs.isEmpty { state.isSheetPresented = false }
                return discard(stagedURLs)

            case let .sheetPresented(isPresented):
                state.isSheetPresented = isPresented
                return .none

            case .barTapped:
                state.isSheetPresented = true
                return .none

            case .delegate:
                return .none
            }
        }
    }

    /// Best effort delete of staged temp files once their jobs finish or are removed. Binds the
    /// dependency locally so the `@Sendable` effect closure doesn't capture `self`.
    private func discard(_ urls: [URL]) -> Effect<Action> {
        guard !urls.isEmpty else { return .none }
        let uploadStaging = self.uploadStaging
        return .run { _ in await uploadStaging.discard(urls) }
    }

    private func upload(_ job: UploadJob, serverURL: URL) -> Effect<Action> {
        let filesClient = self.filesClient
        return .run { send in
            let (progress, continuation) = AsyncStream<Double>.makeStream()
            // Throttle the callbacks (URLSession fires many) so each one does not force a full
            // state diff or view update.
            let lastReported = LockIsolated(0.0)

            let result = await withTaskGroup(
                of: Void.self, returning: Result<FileItem, FilesClientError>.self
            ) { group in
                group.addTask {
                    for await fraction in progress {
                        await send(.progress(id: job.id, fraction))
                    }
                }
                let result = await apiResult {
                    try await filesClient.uploadFile(serverURL, job.fileURL, job.fileName, job.destination) { fraction in
                        let shouldForward = lastReported.withValue { last -> Bool in
                            guard fraction >= 1 || fraction - last >= 0.02 else { return false }
                            last = fraction
                            return true
                        }
                        if shouldForward { continuation.yield(fraction) }
                    }
                }
                continuation.finish()
                await group.waitForAll()
                return result
            }
            await send(.uploadResponse(id: job.id, result))
        }
        .cancellable(id: CancelID.job(job.id))
    }

    private static func message(for error: FilesClientError) -> String {
        switch error {
        case let .serverMessage(_, message): message
        case .sessionExpired, .rateLimited: error.userMessage
        default: L10n.Uploads.failedGeneric
        }
    }
}

private extension UploadsFeature.State {
    var finishSummary: UploadsFeature.FinishSummary {
        let completed = jobs.filter { $0.status == .completed }
        return UploadsFeature.FinishSummary(
            uploadedCount: completed.count,
            failedCount: jobs.filter { $0.status.isFailed }.count,
            lastDestination: completed.last?.destination,
            changedPaths: Set(completed.map(\.destination))
        )
    }
}
