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

    func body(content: Content) -> some View {
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
