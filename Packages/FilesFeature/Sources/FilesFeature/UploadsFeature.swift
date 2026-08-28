import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

/// The app-wide upload queue. Owned by `MainTabFeature` so its state and effects outlive any
/// folder screen or tab switch. Files upload one at a time (sequential, matching
/// `BrowseFeature.startBulkDownload`); each job targets the folder it was started from and
/// tells the parent to re-fetch that folder on success.
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

    public struct FinishSummary: Equatable, Sendable {
        public var uploadedCount: Int
        public var failedCount: Int
        public var lastDestination: String?
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

        /// "N of M" for the bar — M is the whole batch, N the 1-based position of the file
        /// currently going out (a new batch clears finished jobs first, so this stays honest).
        var batchTotal: Int { jobs.count }
        var batchPosition: Int {
            min(jobs.count, jobs.filter(\.status.isTerminal).count + (currentJob == nil ? 0 : 1))
        }
    }

    public enum Action: Equatable, Sendable {
        case enqueue([PendingUpload])
        /// The app returned to the foreground — a default `URLSession` upload can't run while
        /// the app is suspended, so anything still `.uploading` or `.failed` is restarted.
        case appResumed
        case startNextIfIdle
        case progress(id: UUID, Double)
        case uploadResponse(id: UUID, Result<FileItem, FilesClientError>)
        case cancelJobTapped(id: UUID)
        case cancelAllTapped
        case retryTapped(id: UUID)
        case retryAllFailedTapped
        case clearCompletedTapped
        case sheetPresented(Bool)
        case barTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case folderContentsChanged(path: String)
            case queueFinished(FinishSummary)
        }
    }

    @Dependency(\.filesClient) var filesClient
    private enum CancelID: Hashable { case job(UUID) }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .enqueue(pending):
                guard !pending.isEmpty else { return .none }
                // A fresh batch starts from a clean slate so the bar's "N of M" is honest.
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
                let stalled = state.jobs.filter { $0.status.isFailed || $0.status == .uploading }
                guard !stalled.isEmpty else { return .none }
                var effects: [Effect<Action>] = []
                for job in stalled {
                    state.jobs[id: job.id]?.status = .queued
                    state.jobs[id: job.id]?.progress = 0
                    effects.append(.cancel(id: CancelID.job(job.id)))
                }
                effects.append(.send(.startNextIfIdle))
                return .merge(effects)

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
                guard state.jobs[id: id] != nil else { return .none }
                switch result {
                case .success:
                    state.jobs[id: id]?.status = .completed
                    state.jobs[id: id]?.progress = 1
                case let .failure(error):
                    state.jobs[id: id]?.status = .failed(Self.message(for: error))
                }
                let destination = state.jobs[id: id]?.destination
                let didSucceed = result.isSuccess

                if state.jobs.contains(where: { $0.status == .queued }) {
                    return .merge(
                        didSucceed ? .send(.delegate(.folderContentsChanged(path: destination ?? ""))) : .none,
                        .send(.startNextIfIdle)
                    )
                }
                // Batch drained.
                return .merge(
                    didSucceed ? .send(.delegate(.folderContentsChanged(path: destination ?? ""))) : .none,
                    .send(.delegate(.queueFinished(state.finishSummary)))
                )

            case let .cancelJobTapped(id):
                state.jobs.remove(id: id)
                if state.jobs.isEmpty { state.isSheetPresented = false }
                return .merge(.cancel(id: CancelID.job(id)), .send(.startNextIfIdle))

            case .cancelAllTapped:
                let cancels = state.jobs.map { Effect<Action>.cancel(id: CancelID.job($0.id)) }
                state.jobs.removeAll()
                state.isSheetPresented = false
                return .merge(cancels)

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

            case .clearCompletedTapped:
                state.jobs.removeAll { $0.status.isTerminal }
                if state.jobs.isEmpty { state.isSheetPresented = false }
                return .none

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

    private func upload(_ job: UploadJob, serverURL: URL) -> Effect<Action> {
        let filesClient = self.filesClient
        return .run { send in
            // Throttle the progress callbacks (URLSession fires many) so each doesn't force a
            // full state diff + re-render.
            let lastReported = LockIsolated(0.0)
            let result = await apiResult {
                try await filesClient.uploadFile(serverURL, job.fileURL, job.fileName, job.destination) { fraction in
                    let shouldForward = lastReported.withValue { last -> Bool in
                        guard fraction >= 1 || fraction - last >= 0.02 else { return false }
                        last = fraction
                        return true
                    }
                    if shouldForward {
                        Task { await send(.progress(id: job.id, fraction)) }
                    }
                }
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
        UploadsFeature.FinishSummary(
            uploadedCount: jobs.filter { $0.status == .completed }.count,
            failedCount: jobs.filter { $0.status.isFailed }.count,
            lastDestination: jobs.last { $0.status == .completed }?.destination
        )
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}
