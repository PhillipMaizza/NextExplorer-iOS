import DesignSystem
import SwiftUI

private enum Constants {
    static let closeButtonInset: CGFloat = .space16
    static let contentSpacing: CGFloat = .space16
}

/// Full-screen container for non-streamable files (images, PDFs, documents, ...): shows a
/// spinner while `FilesClient.previewFile` downloads, then `QuickLookPreview` once it's
/// ready. Unlike `FileInfoSheet`, there's no `presentationDetents`-resize problem here —
/// `fullScreenCover` is always full-screen regardless of content, so the loading state can
/// live inside the same cover without needing a separate sheet identity to swap to.
struct FilePreviewContainerView: View {
    let fileURL: URL?
    let errorMessage: String?
    let onDismiss: () -> Void
    var onShareLink: (() -> Void)?
    var onDownload: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        content
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                DSCloseButton(action: onDismiss)
                    .padding(Constants.closeButtonInset)
            }
            .overlay(alignment: .bottomTrailing) {
                PreviewActionBar {
                    // order: system share | create link | download | delete
                    SystemShareButton(localFileURL: fileURL)
                    if let onShareLink {
                        PreviewChipButton(icon: IconKit.shareLink, action: onShareLink)
                    }
                    if let onDownload {
                        PreviewChipButton(icon: IconKit.download, action: onDownload)
                    }
                    if let onDelete {
                        PreviewChipButton(icon: IconKit.delete, tint: .negative, action: onDelete)
                    }
                }
                .padding(Constants.closeButtonInset)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let fileURL {
            QuickLookPreview(url: fileURL)
                .ignoresSafeArea()
        } else {
            statusContent
        }
    }

    private var statusContent: some View {
        VStack(spacing: Constants.contentSpacing) {
            if let errorMessage {
                IconKit.warning
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.negative)
                    .frame(width: .iconMedium, height: .iconMedium)
                Text(errorMessage).type(.body1(.regular), style: .secondary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
