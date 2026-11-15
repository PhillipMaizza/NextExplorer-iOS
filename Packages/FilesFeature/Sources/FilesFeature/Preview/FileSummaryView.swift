import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .size64
    /// The side of an audio file's cover art, shown in place of its icon.
    static let artworkSize: CGFloat = .size192
    static let headerSpacing: CGFloat = .space8
    static let contentSpacing: CGFloat = .space24
    static let horizontalPadding: CGFloat = .space24
    /// A full width DS button sized like a sheet action, not stretched across an iPad.
    static let actionWidth: CGFloat = 240
}

/// A file shown by what it is rather than its content, for a file with no viewer: its icon, name,
/// type and size centered, then an optional note and button. The unsupported file screen and the
/// gallery's archive page use it.
struct FileSummaryView<Action: View>: View {
    let item: FileItem
    var message: String?
    /// When set, an audio file shows its cover art (when its tags carry one) in place of the icon.
    var artworkServerURL: URL?
    @ViewBuilder var action: () -> Action

    @ViewBuilder
    private var icon: some View {
        if item.isAudio, let artworkServerURL {
            ThumbnailImage(
                serverURL: artworkServerURL,
                path: item.id,
                signature: item.cacheSignature,
                fallbackIcon: IconKit.document,
                fallbackKind: item.kind,
                iconTint: Color.secondaryDS,
                fallbackSize: Constants.iconSize,
                maxPixelDimension: Constants.artworkSize * 3
            )
            .frame(maxWidth: Constants.artworkSize, maxHeight: Constants.artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: .radiusControl, style: .continuous))
        } else {
            FileTypeIcon(kind: item.kind)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
        }
    }

    var body: some View {
        VStack(spacing: Constants.contentSpacing) {
            Spacer()

            VStack(spacing: Constants.headerSpacing) {
                icon

                Text(item.name)
                    .type(.headline3, style: .primaryOnSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(item.previewTypeText)
                    .type(.body2(.regular), style: .secondary)
                Text(FileSizeFormat.string(item.size))
                    .type(.body2(.regular), style: .secondary)
            }

            if let message {
                Text(message)
                    .type(.body2(.regular), style: .secondary)
                    .multilineTextAlignment(.center)
            }

            action()
                .frame(maxWidth: Constants.actionWidth)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Constants.horizontalPadding)
        .backgroundGradient()
    }
}

extension FileItem {
    /// The file's type as a preview names it: its extension in capitals, or "File" without one.
    var previewTypeText: String {
        kind.isEmpty ? L10n.UnsupportedPreview.genericType : kind.uppercased()
    }
}

extension FileSummaryView where Action == EmptyView {
    init(item: FileItem, message: String?) {
        self.init(item: item, message: message) { EmptyView() }
    }
}

#Preview("Cannot open") {
    FileSummaryView(
        item: FileItem(name: "disk.img", path: "", dateModified: .distantPast, size: 6_144, kind: "img"),
        message: L10n.UnsupportedPreview.cannotOpen
    )
}

#Preview("With action") {
    FileSummaryView(
        item: FileItem(name: "photos.zip", path: "", dateModified: .distantPast, size: 52_428_800, kind: "zip")
    ) {
        DSButton(L10n.Browse.open, icon: IconKit.openInApp, style: .primary) {}
    }
}

#Preview("No type") {
    FileSummaryView(
        item: FileItem(name: "LICENSE", path: "", dateModified: .distantPast, size: 1_024, kind: ""),
        message: L10n.UnsupportedPreview.cannotOpen
    )
}
