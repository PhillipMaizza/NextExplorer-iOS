import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
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
        /// Mac: where the user chose to save it in Finder; `nil` saves into the Downloads tab.
        public var saveTarget: DownloadSaveRequest.Target?
        /// Mac: where a finished save landed, for Show in Finder.
        public var savedURL: URL?

        public init(id: UUID, item: FileItem, status: Status, saveTarget: DownloadSaveRequest.Target? = nil) {
            self.id = id
            self.item = item
            self.status = status
            self.saveTarget = saveTarget
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

        /// iPhone and iPad: where Save to Device puts this item.
        public var deviceDestination: DeviceSaveDestination {
            DeviceSaveDestination.destination(forKind: item.kind)
        }

        /// What the saved file is called: folders arrive as `<name>.zip`, except a Mac save,
        /// which recreates the folder itself.
        public var fileName: String {
            item.isDirectory && saveTarget == nil ? "\(item.name).\(Constants.folderArchiveExtension)" : item.name
        }
    }

    /// Reported to the parent when the queue drains, so it can confirm and refresh the tabs.
    public struct FinishSummary: Equatable, Sendable {
        public var savedCount: Int
        public var failedCount: Int
        /// Mac: the last item saved in Finder, which the confirmation names and reveals.
        public var lastSavedURL: URL?
        /// iPhone and iPad: items that went to Photos.
        public var photosCount = 0
        /// iPhone and iPad: staged files waiting for the Save to Files panel.
        public var exportURLs: [URL] = []
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

        var savedCount: Int {
            jobs.filter { $0.status == .completed }.count
        }

        /// Mac: the last finished save's location in Finder.
        var lastSavedURL: URL? {
            jobs.last { $0.status == .completed && $0.savedURL != nil }?.savedURL
        }
    }

    public enum Action: Equatable, Sendable {
        case enqueue([FileItem])
        /// Mac: items to save where the user chose in Finder.
        case enqueueSaves([DownloadSaveRequest])
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
    @Dependency(\.deviceSaver) var deviceSaver
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date
    private enum CancelID: Hashable { case job(UUID) }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .enqueue(requested):
                #if os(macOS)
                    let items = requested
                #else
                    // Save to Device takes files only: a folder has no single file to hand to Photos or Files.
                    let items = requested.filter { !$0.isDirectory }
                #endif
                guard !items.isEmpty else { return .none }
                if !state.isActive {
                    state.jobs.removeAll { $0.status.isTerminal }
                }
                for item in items {
                    state.jobs.append(DownloadJob(id: uuid(), item: item, status: .queued))
                }
                return .send(.startNextIfIdle)

            case let .enqueueSaves(requests):
                guard !requests.isEmpty else { return .none }
                if !state.isActive {
                    state.jobs.removeAll { $0.status.isTerminal }
                }
                for request in requests {
                    state.jobs.append(DownloadJob(
                        id: uuid(),
                        item: request.item,
                        status: .queued,
                        saveTarget: request.target
                    ))
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
                case let .success(url):
                    state.jobs[id: id]?.status = .completed
                    #if os(macOS)
                        if state.jobs[id: id]?.saveTarget != nil {
                            state.jobs[id: id]?.savedURL = url
                        }
                    #else
                        if state.jobs[id: id]?.deviceDestination == .files {
                            state.jobs[id: id]?.savedURL = url
                        }
                    #endif
                    saved = .send(.delegate(.itemSaved))
                case let .failure(error):
                    state.jobs[id: id]?.status = .failed(Self.message(for: error))
                }
                if state.jobs.contains(where: { $0.status == .queued }) {
                    return .merge(saved, .send(.startNextIfIdle))
                }
                return .concatenate(saved, .send(.delegate(.queueFinished(state.finishSummary))))

            case let .cancelJobTapped(id):
                discardStaged(state.jobs[id: id].map { [$0] } ?? [])
                let wasPending = state.jobs[id: id].map { !$0.status.isTerminal } ?? false
                state.jobs.remove(id: id)
                if state.jobs.isEmpty {
                    state.isSheetPresented = false
                }
                // Cancelling the last pending job means no download response will announce the
                // drain, so items that already landed still need their confirmation and refresh.
                let finished: Effect<Action> = wasPending && !state.isActive && state.savedCount > 0
                    ? .send(.delegate(.queueFinished(state.finishSummary)))
                    : .none
                return .merge(.cancel(id: CancelID.job(id)), .send(.startNextIfIdle), finished)

            case .cancelAllTapped:
                discardStaged(Array(state.jobs))
                let cancels = state.jobs.map { Effect<Action>.cancel(id: CancelID.job($0.id)) }
                let finished: Effect<Action> = state.isActive && state.savedCount > 0
                    ? .send(.delegate(.queueFinished(state.finishSummary)))
                    : .none
                state.jobs.removeAll()
                state.isSheetPresented = false
                return .merge(cancels + [finished])

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
        let deviceSaver = deviceSaver
        return .run { send in await BackgroundActivity.whileTransferring(name: Self.activityName) {
            let (progress, continuation) = AsyncStream<TransferProgress>
                .makeStream(bufferingPolicy: .bufferingNewest(1))

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
                        #if os(macOS)
                            if let target = job.saveTarget {
                                return try await MacDownloadSaving.save(
                                    DownloadSaveRequest(item: job.item, target: target),
                                    serverURL: serverURL,
                                    filesClient: filesClient
                                ) { update in
                                    continuation.yield(update)
                                }
                            }
                        #endif
                        #if os(macOS)
                            let temporaryURL = try await filesClient.downloadItem(serverURL, job.item) { update in
                                continuation.yield(update)
                            }
                            defer { try? FileManager.default.removeItem(at: temporaryURL) }
                            try Task.checkCancellation()
                            do {
                                return try localDownloadStore.save(temporaryURL, job.fileName, scope)
                            } catch {
                                throw FilesClientError.decoding(error.localizedDescription)
                            }
                        #else
                            return try await Self.saveToDevice(
                                job.item, serverURL: serverURL, filesClient: filesClient, deviceSaver: deviceSaver
                            ) { update in
                                continuation.yield(update)
                            }
                        #endif
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
        } }
        .cancellable(id: CancelID.job(job.id))
    }

    static let activityName = "NextExplorer download"

    #if os(iOS)
        /// Downloads the file, stages it under its own name, and sends it where its kind belongs.
        /// Pictures and videos go to Photos and the staged copy is dropped; anything else stays staged
        /// for the Save to Files panel. Returns the staged URL.
        private static func saveToDevice(
            _ item: FileItem,
            serverURL: URL,
            filesClient: FilesClient,
            deviceSaver: DeviceSaver,
            onProgress: @escaping @Sendable (TransferProgress) -> Void
        ) async throws -> URL {
            let temporaryURL = try await filesClient.downloadItem(serverURL, item, onProgress)
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw CancellationError()
            }
            let staged: URL
            do {
                staged = try deviceSaver.stage(temporaryURL, item.name)
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw FilesClientError.decoding(error.localizedDescription)
            }
            guard case let .photos(isVideo) = DeviceSaveDestination.destination(forKind: item.kind) else {
                return staged
            }
            defer { deviceSaver.discard([staged]) }
            do {
                try await deviceSaver.saveToPhotos(staged, isVideo)
            } catch DeviceSaveError.photosAccessDenied {
                throw FilesClientError.serverMessage(statusCode: 0, message: L10n.DownloadQueue.photosAccessDenied)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FilesClientError.serverMessage(statusCode: 0, message: L10n.DownloadQueue.photosSaveFailed)
            }
            return staged
        }
    #endif

    private func discardStaged(_ jobs: [DownloadJob]) {
        #if os(iOS)
            let staged = jobs.compactMap { $0.deviceDestination == .files ? $0.savedURL : nil }
            if !staged.isEmpty {
                deviceSaver.discard(staged)
            }
        #endif
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
        let completed = jobs.filter { $0.status == .completed }
        var summary = DownloadQueueFeature.FinishSummary(
            savedCount: completed.count,
            failedCount: jobs.filter(\.status.isFailed).count,
            lastSavedURL: nil
        )
        #if os(macOS)
            summary.lastSavedURL = lastSavedURL
        #else
            summary.photosCount = completed.filter { $0.deviceDestination != .files }.count
            summary.exportURLs = completed.compactMap { $0.deviceDestination == .files ? $0.savedURL : nil }
        #endif
        return summary
    }
}
