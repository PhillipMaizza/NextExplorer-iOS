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
    var onShare: (() -> Void)?
    var onDownload: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            content

            HStack(spacing: Constants.closeButtonInset) {
                DSCloseButton(action: onDismiss)
                Spacer()
                if let onShare { previewToolbarButton(IconKit.shareLink, action: onShare) }
                if let onDownload { previewToolbarButton(IconKit.download, action: onDownload) }
                if let onDelete { previewToolbarButton(IconKit.delete, tint: Color.negative, action: onDelete) }
            }
            .padding(Constants.closeButtonInset)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }

    private func previewToolbarButton(_ icon: Image, tint: Color = .primaryDS, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(width: .iconXSmall, height: .iconXSmall)
                .padding(.space8)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(DSHapticButtonStyle())
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
