import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

@MainActor
enum UploadReviewFormat {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

/// One staged file in the upload review list: tappable thumbnail (opens the QuickLook batch
/// preview), name + size, and a remove button.
struct UploadFileRow: View {
    let file: PickedFile
    let onPreview: () -> Void
    let onRemove: () -> Void

    private enum Metrics {
        static let thumbnailSize: CGFloat = .iconLarge
        static let removeButtonSize: CGFloat = .iconSmall
        static let rowSpacing: CGFloat = .space12
        static let rowTextSpacing: CGFloat = .space2
    }

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            Button(action: onPreview) {
                thumbnail
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Uploads.reviewPreviewFile(file.fileName))
            VStack(alignment: .leading, spacing: Metrics.rowTextSpacing) {
                Text(file.fileName)
                    .type(.body2(.regular), style: .primaryOnSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(UploadReviewFormat.byteFormatter.string(fromByteCount: file.size))
                    .type(.body3(.regular), style: .secondary)
            }
            Spacer(minLength: Metrics.rowSpacing)
            Button(action: onRemove) {
                IconKit.closeCircle
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.removeButtonSize, height: Metrics.removeButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.remove)
        }
        .padding(.vertical, .space4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let kind = (file.fileName as NSString).pathExtension.lowercased()
        if FileItem.isImageKind(kind), kind != "svg" {
            AsyncImage(url: file.fileURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    FileTypeIcon(kind: kind)
                default:
                    ThumbnailLoadingPlaceholder()
                }
            }
            .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: .radiusSmall))
        } else if FileItem.isVideoKind(kind) {
            VideoThumbnailView(url: file.fileURL, size: Metrics.thumbnailSize)
        } else {
            FileTypeIcon(kind: kind)
                .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
        }
    }
}
