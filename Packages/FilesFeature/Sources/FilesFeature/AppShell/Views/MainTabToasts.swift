import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct MainTabToasts: ViewModifier {
    let store: StoreOf<MainTabFeature>
    let extraBottomInset: CGFloat

    @State private var uploadMessage: DSToastMessage?
    @State private var downloadMessage: DSToastMessage?
    #if os(macOS)
        @Environment(\.locale) private var locale
        @State private var uploadTransfer: DSToastMessage?
        @State private var downloadTransfer: DSToastMessage?
        @State private var closedTransfers: Set<TransferQueue> = []

        private enum TransferQueue: String {
            case uploads
            case downloads
        }
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
            outcomes(content)
                .dsToast(transferBinding(.uploads, $uploadTransfer), extraBottomInset: extraBottomInset)
                .dsToast(transferBinding(.downloads, $downloadTransfer), extraBottomInset: extraBottomInset)
                .onChange(of: transferMessage(.uploads), initial: true) { _, message in
                    uploadTransfer = closedTransfers.contains(.uploads) ? nil : message
                }
                .onChange(of: transferMessage(.downloads), initial: true) { _, message in
                    downloadTransfer = closedTransfers.contains(.downloads) ? nil : message
                }
                .onChange(of: store.uploads.isActive) { _, isActive in
                    if !isActive {
                        closedTransfers.remove(.uploads)
                    }
                }
                .onChange(of: store.downloadQueue.isActive) { _, isActive in
                    if !isActive {
                        closedTransfers.remove(.downloads)
                    }
                }
        #else
            outcomes(content)
        #endif
    }

    private func outcomes(_ content: Content) -> some View {
        content
            .dsToast(
                Binding(
                    get: { uploadMessage },
                    set: {
                        uploadMessage = $0
                        if $0 == nil {
                            store.send(.dismissUploadToast)
                        }
                    }
                ),
                extraBottomInset: extraBottomInset
            )
            .dsToast(
                Binding(
                    get: { downloadMessage },
                    set: {
                        downloadMessage = $0
                        if $0 == nil {
                            store.send(.dismissDownloadToast)
                        }
                    }
                ),
                extraBottomInset: extraBottomInset
            )
            .onChange(of: store.uploadToast, initial: true) { _, toast in
                uploadMessage = toast.map(uploadToastMessage)
            }
            .onChange(of: store.downloadToast, initial: true) { _, message in
                downloadMessage = message.map(downloadToastMessage)
            }
    }

    #if os(macOS)
        private func transferBinding(
            _ queue: TransferQueue,
            _ message: Binding<DSToastMessage?>
        ) -> Binding<DSToastMessage?> {
            Binding(
                get: { message.wrappedValue },
                set: {
                    if $0 == nil, message.wrappedValue != nil {
                        closedTransfers.insert(queue)
                    }
                    message.wrappedValue = $0
                }
            )
        }

        private func transferMessage(_ queue: TransferQueue) -> DSToastMessage? {
            let titles = TransferStatusBars(store: store)
            switch queue {
            case .uploads:
                guard store.uploads.isActive else { return nil }
                return .transfer(
                    titles.uploadBarTitle,
                    id: queue.rawValue,
                    icon: IconKit.uploadFill,
                    fraction: store.uploads.overallProgress,
                    fileName: store.uploads.currentJob?.fileName,
                    timeLeft: DownloadProgressText.timeLeft(store.uploads.estimatedSecondsRemaining, locale: locale),
                    actionTitle: L10n.Menu.showAll,
                    action: { store.send(.uploads(.barTapped)) },
                    cancelTitle: L10n.Uploads.cancelAll,
                    cancel: { store.send(.uploads(.cancelAllTapped)) }
                )
            case .downloads:
                guard store.downloadQueue.isActive else { return nil }
                return .transfer(
                    titles.downloadBarTitle,
                    id: queue.rawValue,
                    icon: IconKit.downloadFill,
                    fraction: store.downloadQueue.currentJob?.progress,
                    fileName: store.downloadQueue.currentJob?.fileName,
                    timeLeft: DownloadProgressText.timeLeft(
                        store.downloadQueue.currentJob?.estimatedSecondsRemaining,
                        locale: locale
                    ),
                    actionTitle: L10n.Menu.showAll,
                    action: { store.send(.downloadQueue(.barTapped)) },
                    cancelTitle: L10n.DownloadQueue.cancelAll,
                    cancel: { store.send(.downloadQueue(.cancelAllTapped)) }
                )
            }
        }
    #endif

    private func uploadToastMessage(_ toast: MainTabFeature.UploadToast) -> DSToastMessage {
        guard let destination = toast.openDestination else { return .success(toast.message) }
        return .success(
            toast.message,
            detail: destination.split(separator: "/").last.map(String.init),
            actionTitle: L10n.Browse.open
        ) {
            store.send(.openUploadedLocation(destination))
        }
    }

    private func downloadToastMessage(_ message: String) -> DSToastMessage {
        #if os(macOS)
            if let savedURL = store.lastSavedDownloadURL {
                return .success(message, actionTitle: L10n.Browse.showInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                }
            }
        #endif
        return .success(message)
    }
}
