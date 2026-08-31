import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .size64
    static let headerSpacing: CGFloat = .space8
    static let contentSpacing: CGFloat = .space24
    static let horizontalPadding: CGFloat = .space24
}

/// Full-screen stand-in for a file the app has no viewer for (`FileItem.isUnsupportedForPreview`)
/// — a font, a disk image, a `.webm` AVFoundation can't decode. Mirrors the Files app: the
/// file's icon, name, type and size centered on screen, a `DSInfoCard` saying it can't be
/// opened, and whatever of the shared `previewChrome` action bar the caller wires up. On the
/// browse tab that's the full set (share / share link / rename / download / delete); inside
/// `ArchiveBrowserView` it's just `systemShare` of the extracted local file.
struct UnsupportedFilePreviewView: View {
    let item: FileItem
    let systemShare: SystemShareSource
    let onDismiss: () -> Void
    var onShareLink: (() -> Void)?
    var onRename: (() -> Void)?
    var onDownload: (() -> Void)?
    var onDelete: (() -> Void)?

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var typeText: String {
        item.kind.isEmpty ? L10n.UnsupportedPreview.genericType : item.kind.uppercased()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Constants.contentSpacing) {
                Spacer()

                VStack(spacing: Constants.headerSpacing) {
                    FileTypeIcon(kind: item.kind)
                        .frame(width: Constants.iconSize, height: Constants.iconSize)

                    Text(item.name)
                        .type(.headline3, style: .primary(for: .label))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(typeText)
                        .type(.body2(.regular), style: .secondary)
                    Text(Self.byteFormatter.string(fromByteCount: item.size))
                        .type(.body2(.regular), style: .secondary)
                }

                DSInfoCard(L10n.UnsupportedPreview.cannotOpen)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Constants.horizontalPadding)
            .backgroundGradient()
            .previewChrome(
                title: item.name,
                systemShare: systemShare,
                onShareLink: onShareLink,
                onRename: onRename,
                onDownload: onDownload,
                onDelete: onDelete,
                onClose: onDismiss
            )
        }
    }
}

#Preview {
    UnsupportedFilePreviewView(
        item: FileItem(name: "test_X24504889T2", path: "", dateModified: Date(), size: 6_144, kind: "dat"),
        systemShare: .unavailable,
        onDismiss: {}
    )
}
