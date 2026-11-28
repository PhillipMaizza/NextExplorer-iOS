import CoreModels
import DesignSystem
import SwiftUI

/// Full screen container for non streamable files (images, PDFs, documents, ...): shows a
/// spinner while `FilesClient.previewFile` downloads, then `QuickLookPreview` once it's
/// ready. Unlike `FileInfoSheet`, there's no `presentationDetents` resize problem here:
/// `fullScreenCover` is always full screen regardless of content, so the loading state can
/// live inside the same cover without needing a separate sheet identity to swap to.
struct FilePreviewContainerView: View {
    let fileURL: URL?
    let errorMessage: String?
    let onDismiss: () -> Void
    var onShareLink: (() -> Void)?
    var onRename: (() -> Void)?
    var onDownload: (() -> Void)?
    var onDelete: (() -> Void)?
    var file: FileItem?
    #if os(macOS)
        @State private var renderCheck: RenderCheck?
    #endif

    var body: some View {
        NavigationStack {
            content
                .backgroundGradient()
                .previewChrome(
                    title: file?.name ?? fileURL?.lastPathComponent,
                    systemShare: .local(fileURL),
                    onShareLink: onShareLink,
                    onRename: onRename,
                    onDownload: onDownload,
                    onDelete: onDelete,
                    file: file,
                    hasOpenWithPage: hasOpenWithPage,
                    onClose: onDismiss
                )
        }
    }

    @ViewBuilder
    private var content: some View {
        if let fileURL {
            #if os(macOS)
                macDocument(fileURL)
            #else
                QuickLookPreview(url: fileURL)
                    .ignoresSafeArea()
            #endif
        } else {
            statusContent
        }
    }

    private var hasOpenWithPage: Bool {
        #if os(macOS)
            renderCheck?.url == fileURL && renderCheck?.canRender == false && file != nil
        #else
            false
        #endif
    }

    #if os(macOS)
        private struct RenderCheck {
            let url: URL
            let canRender: Bool
        }

        private func macDocument(_ fileURL: URL) -> some View {
            Group {
                if renderCheck?.url != fileURL {
                    DSSpinner()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasOpenWithPage, let file {
                    MacNoPreviewPage(item: file, source: .local(fileURL))
                } else {
                    QuickLookPreview(url: fileURL)
                }
            }
            .task(id: fileURL) {
                let canRender = await QuickLookSupport.rendersContent(of: fileURL)
                guard !Task.isCancelled else { return }
                renderCheck = RenderCheck(url: fileURL, canRender: canRender)
            }
        }
    #endif

    @ViewBuilder
    private var statusContent: some View {
        if let errorMessage {
            PreviewErrorView(message: errorMessage)
        } else {
            DSSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
