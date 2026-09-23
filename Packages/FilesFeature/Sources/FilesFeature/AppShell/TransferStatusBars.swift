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
                label: queue.failedCount == 1 ? L10n.DownloadQueue.barFailedOne : L10n.DownloadQueue.barFailedMany(queue.failedCount),
                onRetry: { store.send(.downloadQueue(.retryAllFailedTapped), animation: .default) },
                onDismiss: { store.send(.downloadQueue(.clearFinishedTapped), animation: .default) },
                onTap: { store.send(.downloadQueue(.barTapped)) }
            )
        }
    }

    private var downloadBarTitle: String {
        let queue = store.downloadQueue
        if queue.remainingCount <= 1, let name = queue.currentJob?.fileName {
            return L10n.DownloadQueue.barTitleOne(name)
        }
        return L10n.DownloadQueue.barTitleMany(queue.remainingCount)
    }

    private var uploadBarTitle: String {
        let uploads = store.uploads
        if uploads.remainingCount <= 1, let name = uploads.currentJob?.fileName {
            return L10n.Uploads.barTitleOne(name)
        }
        return L10n.Uploads.barTitleMany(uploads.remainingCount)
    }
}
