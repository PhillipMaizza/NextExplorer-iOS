import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// The full upload queue, opened by tapping the persistent progress bar. One row per file with
/// live progress, a cancel button while it runs, and retry on failure.
struct UploadsView: View {
    @Bindable var store: StoreOf<UploadsFeature>

    var body: some View {
        #if os(macOS)
            MacTransferQueueSheet(
                title: L10n.Uploads.navigationTitle,
                rows: rows,
                emptyMessage: L10n.Uploads.emptyList,
                canClear: store.hasClearableJobs,
                onCancel: cancel,
                onRetry: retry,
                onClear: clear,
                onClose: close
            )
        #else
            PhoneTransferQueueSheet(
                title: L10n.Uploads.navigationTitle,
                rows: rows,
                emptyIcon: IconKit.upload,
                emptyMessage: L10n.Uploads.emptyList,
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
                case .uploading: .running(progress: job.progress, detail: nil)
                case .completed: .done(destinationLabel(job.destination))
                case let .failed(message): .failed(message)
                }
            }())
        }
    }

    private func cancel(_ id: UUID) {
        store.send(.cancelJobTapped(id: id), animation: DSMotion.listDiff)
    }

    private func retry(_ id: UUID) {
        store.send(.retryTapped(id: id), animation: DSMotion.listDiff)
    }

    private func clear() {
        store.send(.clearFinishedTapped, animation: DSMotion.listDiff)
    }

    private func close() {
        store.send(.sheetPresented(false))
    }

    private func destinationLabel(_ path: String) -> String {
        path.isEmpty ? L10n.Browse.locations : (path as NSString).lastPathComponent
    }
}

#Preview {
    UploadsView(
        store: Store(initialState: UploadsFeature.State(serverURL: URL(string: "https://example.com")!)) {
            UploadsFeature()
        }
    )
}
