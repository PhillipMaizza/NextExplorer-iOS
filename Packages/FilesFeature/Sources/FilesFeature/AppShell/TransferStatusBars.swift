import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// The floating upload and download pills stacked above the tab bar. Each shows live progress
/// while its queue runs, or a failed summary with Retry once it drains with failures.
struct TransferStatusBars: View {
    let store: StoreOf<MainTabFeature>
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: .space8) {
            if store.uploads.isBarVisible {
                uploadStatusBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if store.downloadQueue.isBarVisible {
                downloadStatusBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if store.isOfflineBarVisible {
                offlineStatusBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// The same pill the downloads use, for a run that makes files available offline.
    @ViewBuilder
    private var offlineStatusBar: some View {
        let progress = store.offlineProgress
        if case let .failed(message) = progress.phase {
            TransferFailedBar(
                label: message,
                onRetry: { store.send(.offline(.resyncTapped), animation: .default) },
                onDismiss: { store.send(.offline(.dismissStatusTapped), animation: .default) },
                onTap: {}
            )
        } else {
            TransferProgressBar(
                icon: IconKit.availableOffline,
                title: offlineBarTitle,
                progress: offlineBarProgress,
                detail: progress.phase == .downloading
                    ? L10n.Offline.progressCount(progress.currentFileNumber, progress.filesTotal)
                    : nil,
                cancelLabel: L10n.Common.cancel,
                onTap: {},
                onCancelAll: { store.send(.offline(.cancelTapped), animation: .default) }
            )
        }
    }

    @ViewBuilder
    private var uploadStatusBar: some View {
        if store.uploads.isActive {
            TransferProgressBar(
                icon: IconKit.upload,
                title: uploadBarTitle,
                progress: store.uploads.currentJob?.progress ?? 0,
                cancelLabel: L10n.Uploads.cancelAll,
                onTap: { store.send(.uploads(.barTapped)) },
                onCancelAll: { store.send(.uploads(.cancelAllTapped), animation: .default) }
            )
        } else {
            let count = store.uploads.failedCount
            TransferFailedBar(
                label: count == 1 ? L10n.Uploads.barFailedOne : L10n.Uploads.barFailedMany(count),
                onRetry: { store.send(.uploads(.retryAllFailedTapped), animation: .default) },
                onDismiss: { store.send(.uploads(.clearFinishedTapped), animation: .default) },
                onTap: { store.send(.uploads(.barTapped)) }
            )
        }
    }

    @ViewBuilder
    private var downloadStatusBar: some View {
        let queue = store.downloadQueue
        if queue.isActive {
            TransferProgressBar(
                icon: IconKit.download,
                title: downloadBarTitle,
                progress: queue.currentJob?.progress,
                detail: queue.currentJob.flatMap { DownloadProgressText.detail(for: $0, locale: locale) },
                cancelLabel: L10n.DownloadQueue.cancelAll,
                onTap: { store.send(.downloadQueue(.barTapped)) },
                onCancelAll: { store.send(.downloadQueue(.cancelAllTapped), animation: .default) }
            )
        } else {
            TransferFailedBar(
                label: queue.failedCount == 1
                    ? L10n.DownloadQueue.barFailedOne
                    : L10n.DownloadQueue
                        .barFailedMany(queue.failedCount),
                onRetry: { store.send(.downloadQueue(.retryAllFailedTapped), animation: .default) },
                onDismiss: { store.send(.downloadQueue(.clearFinishedTapped), animation: .default) },
                onTap: { store.send(.downloadQueue(.barTapped)) }
            )
        }
    }

    /// The file an offline run is fetching, or that it is still working out what to fetch.
    var offlineBarTitle: String {
        let progress = store.offlineProgress
        return progress.phase == .downloading && !progress.currentName.isEmpty
            ? L10n.Offline.downloadingName(progress.currentName)
            : L10n.Offline.preparing
    }

    /// `nil` while the run prepares, so the bar shows an indeterminate progress.
    var offlineBarProgress: Double? {
        store.offlineProgress.phase == .downloading ? store.offlineProgress.fractionComplete : nil
    }

    var downloadBarTitle: String {
        let queue = store.downloadQueue
        if queue.remainingCount <= 1, let name = queue.currentJob?.fileName {
            return L10n.DownloadQueue.barTitleOne(name)
        }
        return L10n.DownloadQueue.barTitleMany(queue.remainingCount)
    }

    var uploadBarTitle: String {
        let uploads = store.uploads
        if uploads.remainingCount <= 1, let name = uploads.currentJob?.fileName {
            return L10n.Uploads.barTitleOne(name)
        }
        return L10n.Uploads.barTitleMany(uploads.remainingCount)
    }
}
