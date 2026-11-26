import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The download queue, opened by tapping the progress bar. One row per item with live progress,
/// cancel while it runs, retry on failure, and a shortcut to the Downloads tab.
struct DownloadQueueView: View {
    @Bindable var store: StoreOf<DownloadQueueFeature>
    #if os(macOS)
        var activity: MacDownloadActivity?
    #endif
    @Environment(\.locale) private var locale

    var body: some View {
        #if os(macOS)
            MacTransferQueueSheet(
                icon: IconKit.macDownload,
                title: L10n.DownloadQueue.navigationTitle,
                summary: summary,
                progress: store.jobs.isEmpty ? activity?.fraction : store.overallProgress,
                rows: (activity?.offlineRow).map { [$0] + rows } ?? rows,
                emptyMessage: L10n.DownloadQueue.emptyList,
                canClear: store.hasCompletedJobs,
                canRetryFailed: store.failedCount > 0,
                onCancel: { id in
                    if id == MacDownloadActivity.offlineRowID {
                        activity?.cancelOfflineRow()
                    } else {
                        cancel(id)
                    }
                },
                onRetry: { id in
                    if id == MacDownloadActivity.offlineRowID {
                        activity?.retryOfflineRow()
                    } else {
                        retry(id)
                    }
                },
                onUploadMore: nil,
                onRetryFailed: { store.send(.retryAllFailedTapped, animation: DSMotion.listDiff) },
                onClear: { store.send(.clearCompletedTapped, animation: DSMotion.listDiff) },
                onMinimize: minimize,
                onClose: close
            )
            .onChange(of: activity?.isActive) { wasActive, isActive in
                guard wasActive == true, isActive == false, store.jobs.isEmpty,
                      activity?.offlineRow == nil else { return }
                close()
            }
        #else
            PhoneTransferQueueSheet(
                title: L10n.DownloadQueue.navigationTitle,
                rows: rows,
                emptyIcon: IconKit.download,
                emptyMessage: L10n.DownloadQueue.emptyList,
                canClear: store.hasClearableJobs,
                onCancel: cancel,
                onRetry: retry,
                onClear: clear,
                onClose: close
            )
        #endif
    }

    private var rows: [TransferQueueRow] {
        store.jobs.map { job in
            TransferQueueRow(id: job.id, name: job.fileName, status: {
                switch job.status {
                case .queued: .waiting
                case .downloading: .running(
                        progress: job.progress,
                        detail: DownloadProgressText.detail(for: job, locale: locale)
                    )
                case .completed: .done(savedLabel(job))
                case let .failed(message): .failed(message)
                }
            }(), subtitle: DownloadProgressText.size(of: job, locale: locale))
        }
    }

    #if os(macOS)
        private var summary: TransferQueueSummary {
            if store.jobs.isEmpty, let activity {
                return activity.offlineSummary
            }
            return TransferQueueSummary(
                done: L10n.DownloadQueue.summary(store.savedCount, store.jobs.count),
                failure: store.failedCount > 0 ? TransferFailureText.downloads(store.failedCount) : nil,
                timeLeft: DownloadProgressText.timeLeft(store.currentJob?.estimatedSecondsRemaining, locale: locale)
            )
        }
    #endif

    private func cancel(_ id: UUID) {
        store.send(.cancelJobTapped(id: id), animation: DSMotion.listDiff)
    }

    private func retry(_ id: UUID) {
        store.send(.retryTapped(id: id), animation: DSMotion.listDiff)
    }

    private func clear() {
        store.send(.clearFinishedTapped, animation: DSMotion.listDiff)
    }

    private var minimize: (() -> Void)? {
        #if os(macOS)
            guard store.isActive || activity?.isActive == true else { return nil }
        #else
            guard store.isActive else { return nil }
        #endif
        return close
    }

    private func close() {
        store.send(.sheetPresented(false))
    }

    private func savedLabel(_ job: DownloadQueueFeature.DownloadJob) -> String {
        guard job.receivedBytes > 0 else { return L10n.DownloadQueue.statusSaved }
        return L10n.DownloadQueue.statusSaved + " · " + DownloadProgressText.bytes(job.receivedBytes, locale: locale)
    }
}

private extension DownloadQueueFeature.State {
    static func preview(_ jobs: [DownloadQueueFeature.DownloadJob]) -> Self {
        var state = Self(serverURL: URL(string: "https://example.com") ?? URL(fileURLWithPath: "/"))
        state.jobs = IdentifiedArray(uniqueElements: jobs)
        return state
    }
}

private func previewJob(
    _ name: String, kind: String, status: DownloadQueueFeature.DownloadJob.Status,
    received: Int64 = 0, expected: Int64? = nil, rate: Double? = nil
) -> DownloadQueueFeature.DownloadJob {
    var job = DownloadQueueFeature.DownloadJob(
        id: UUID(),
        item: FileItem(name: name, path: "Files", dateModified: Date(), size: 0, kind: kind),
        status: status
    )
    job.receivedBytes = received
    job.expectedBytes = expected
    job.bytesPerSecond = rate
    return job
}

#Preview("Mixed") {
    DownloadQueueView(
        store: Store(initialState: .preview([
            previewJob(
                "Holiday.mp4",
                kind: "mp4",
                status: .downloading,
                received: 420_000_000,
                expected: 1_600_000_000,
                rate: 12_000_000
            ),
            previewJob("Photos", kind: "directory", status: .downloading, received: 312_000_000),
            previewJob("Report.pdf", kind: "pdf", status: .completed, received: 2_400_000),
            previewJob("Big.iso", kind: "iso", status: .failed("Couldn't reach the server.")),
        ])) {
            DownloadQueueFeature()
        }
    )
}

#Preview("Empty") {
    DownloadQueueView(
        store: Store(initialState: DownloadQueueFeature.State.preview([DownloadQueueFeature.DownloadJob]())) {
            DownloadQueueFeature()
        }
    )
}
