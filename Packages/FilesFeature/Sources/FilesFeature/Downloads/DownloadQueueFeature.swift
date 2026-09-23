import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import NetworkClient

/// The app wide download queue behind every "Download" action. Owned by `MainTabFeature` so a
/// transfer keeps running across folder and tab changes, and torn down with the session. Items
/// download one at a time straight into the Downloads tab: a file streams verbatim, a folder as a
/// zip the server builds on the fly, with live progress for the bar and the queue sheet.
@Reducer
public struct DownloadQueueFeature {
    public struct DownloadJob: Equatable, Sendable, Identifiable {
        public enum Status: Equatable, Sendable {
            case queued, downloading, completed, failed(String)

            var isTerminal: Bool {
                switch self {
                case .completed, .failed: true
                case .queued, .downloading: false
                }
            }

            var isFailed: Bool {
                if case .failed = self {
                    true
                } else {
                    false
                }
            }
        }

        public let id: UUID
        public let item: FileItem
        public var status: Status
        public var receivedBytes: Int64 = 0
        /// `nil` until the server reports a length. A streamed folder zip never does, so its row
        /// and the bar show an indeterminate indicator and a byte count instead of a stuck 0%.
        public var expectedBytes: Int64?
        public var startedAt: Date?
        /// Average rate since the transfer started, steadier for an estimate than an instant rate.
        public var bytesPerSecond: Double?

        public init(id: UUID, item: FileItem, status: Status) {
            self.id = id
            self.item = item
            self.status = status
        }

        public var progress: Double? {
            if status == .completed {
                return 1
            }
            return TransferProgress(receivedBytes: receivedBytes, expectedBytes: expectedBytes).fraction
        }

        /// Seconds left, when both the total and a rate are known.
        public var estimatedSecondsRemaining: Double? {
            guard status == .downloading, let expectedBytes, let bytesPerSecond, bytesPerSecond > 0 else { return nil }
            return max(Double(expectedBytes - receivedBytes), 0) / bytesPerSecond
        }

        /// What the saved file is called: folders arrive as `<name>.zip`.
        public var fileName: String {
            item.isDirectory ? "\(item.name).\(Constants.folderArchiveExtension)" : item.name
        }
    }

    /// Reported to the parent when the queue drains, so it can confirm and refresh the tabs.
    public struct FinishSummary: Equatable, Sendable {
        public var savedCount: Int
        public var failedCount: Int
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        public var jobs: IdentifiedArrayOf<DownloadJob> = []
        public var isSheetPresented = false
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) public var downloadScope = ""

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        public var isActive: Bool {
            jobs.contains { !$0.status.isTerminal }
        }

        public var failedCount: Int {
            jobs.filter(\.status.isFailed).count
        }

        public var isBarVisible: Bool {
            isActive || failedCount > 0
        }

        var currentJob: DownloadJob? {
            jobs.first { $0.status == .downloading }
        }

        var hasClearableJobs: Bool {
            jobs.contains { $0.status.isTerminal }
        }

        var remainingCount: Int {
            jobs.filter { !$0.status.isTerminal }.count
        }
    }

    public enum Action: Equatable, Sendable {
        case enqueue([FileItem])
        case startNextIfIdle
        case progress(id: UUID, TransferProgress)
        case downloadResponse(id: UUID, Result<URL, FilesClientError>)
        case cancelJobTapped(id: UUID)
        case cancelAllTapped
        case retryTapped(id: UUID)
        case retryAllFailedTapped
        case clearFinishedTapped
        case sheetPresented(Bool)
        case barTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            /// One item landed in the Downloads tab.
            case itemSaved
            case queueFinished(FinishSummary)
        }
    }

    private enum Constants {
        static let folderArchiveExtension = "zip"
        /// A rate needs a little history before it means anything.
        static let minimumElapsedForRate: TimeInterval = 1
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.localDownloadStore) var localDownloadStore
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date
    private enum CancelID: Hashable { case job(UUID) }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .enqueue(items):
                guard !items.isEmpty else { return .none }
                if !state.isActive {
                    state.jobs.removeAll { $0.status.isTerminal }
                }
                for item in items {
                    state.jobs.append(DownloadJob(id: uuid(), item: item, status: .queued))
                }
                return .send(.startNextIfIdle)

            case .startNextIfIdle:
                guard state.currentJob == nil,
                      let next = state.jobs.first(where: { $0.status == .queued })
                else { return .none }
                state.jobs[id: next.id]?.status = .downloading
                state.jobs[id: next.id]?.resetTransfer(startedAt: date.now)
                return download(next, serverURL: state.serverURL, scope: state.downloadScope)

            case let .progress(id, progress):
                guard var job = state.jobs[id: id], job.status == .downloading else { return .none }
                job.receivedBytes = progress.receivedBytes
                job.expectedBytes = progress.expectedBytes
                if let startedAt = job.startedAt {
                    let elapsed = date.now.timeIntervalSince(startedAt)
                    if elapsed >= Constants.minimumElapsedForRate {
                        job.bytesPerSecond = Double(progress.receivedBytes) / elapsed
                    }
                }
                state.jobs[id: id] = job
                return .none

            case let .downloadResponse(id, result):
                guard state.jobs[id: id] != nil else { return .none }
                var saved: Effect<Action> = .none
                switch result {
                case .success:
                    state.jobs[id: id]?.status = .completed
                    saved = .send(.delegate(.itemSaved))
                case let .failure(error):
                    state.jobs[id: id]?.status = .failed(Self.message(for: error))
                }
                if state.jobs.contains(where: { $0.status == .queued }) {
                    return .merge(saved, .send(.startNextIfIdle))
                }
                return .concatenate(saved, .send(.delegate(.queueFinished(state.finishSummary))))

            case let .cancelJobTapped(id):
                state.jobs.remove(id: id)
                if state.jobs.isEmpty {
                    state.isSheetPresented = false
                }
                return .merge(.cancel(id: CancelID.job(id)), .send(.startNextIfIdle))

            case .cancelAllTapped:
                let cancels = state.jobs.map { Effect<Action>.cancel(id: CancelID.job($0.id)) }
                state.jobs.removeAll()
                state.isSheetPresented = false
                return .merge(cancels)

            case let .retryTapped(id):
                guard state.jobs[id: id]?.status.isFailed == true else { return .none }
                state.jobs[id: id]?.status = .queued
                state.jobs[id: id]?.resetTransfer(startedAt: nil)
                return .send(.startNextIfIdle)

            case .retryAllFailedTapped:
                let failed = state.jobs.filter(\.status.isFailed)
                guard !failed.isEmpty else { return .none }
                for job in failed {
                    state.jobs[id: job.id]?.status = .queued
                    state.jobs[id: job.id]?.resetTransfer(startedAt: nil)
                }
                return .send(.startNextIfIdle)

            case .clearFinishedTapped:
                state.jobs.removeAll { $0.status.isTerminal }
                if state.jobs.isEmpty {
                    state.isSheetPresented = false
                }
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

    private func download(_ job: DownloadJob, serverURL: URL, scope: String) -> Effect<Action> {
        let filesClient = filesClient
        let localDownloadStore = localDownloadStore
        return .run { send in
            let (progress, continuation) = AsyncStream<TransferProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))

            let result = await withTaskGroup(
                of: Void.self, returning: Result<URL, FilesClientError>?.self
            ) { group in
                group.addTask {
                    for await update in progress {
                        await send(.progress(id: job.id, update))
                    }
                }
                let result: Result<URL, FilesClientError>?
                do {
                    result = try await apiResult {
                        // A pooled keep alive socket a proxy dropped silently would stall this POST
                        // (never retried automatically) until the inactivity timeout, surfacing as
                        // "couldn't reach the server". Start every item on a fresh connection.
                        await filesClient.flushDownloadConnections()
                        let temporaryURL = try await filesClient.downloadItem(serverURL, job.item) { update in
                            continuation.yield(update)
                        }
                        defer { try? FileManager.default.removeItem(at: temporaryURL) }
                        try Task.checkCancellation()
                        do {
                            return try localDownloadStore.save(temporaryURL, job.fileName, .documents, scope)
                        } catch {
                            throw FilesClientError.decoding(error.localizedDescription)
                        }
                    }
                } catch {
                    result = nil
                }
                continuation.finish()
                await group.waitForAll()
                return result
            }
            guard let result, !Task.isCancelled else { return }
            await send(.downloadResponse(id: job.id, result))
        }
        .cancellable(id: CancelID.job(job.id))
    }

    private static func message(for error: FilesClientError) -> String {
        switch error {
        case let .serverMessage(_, message): message
        default: error.userMessage
        }
    }
}

private extension DownloadQueueFeature.DownloadJob {
    mutating func resetTransfer(startedAt: Date?) {
        receivedBytes = 0
        expectedBytes = nil
        bytesPerSecond = nil
        self.startedAt = startedAt
    }
}

private extension DownloadQueueFeature.State {
    var finishSummary: DownloadQueueFeature.FinishSummary {
        DownloadQueueFeature.FinishSummary(
            savedCount: jobs.filter { $0.status == .completed }.count,
            failedCount: jobs.filter(\.status.isFailed).count
        )
    }
}
