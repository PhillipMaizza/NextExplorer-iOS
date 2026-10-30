import CoreModels
import DesignSystem
import Localization
import SwiftUI
#if os(macOS)
    import AppKit
    import UniformTypeIdentifiers
#endif

private enum Constants {
    static let iconSize: CGFloat = .size64
    static let headerSpacing: CGFloat = .space8
    static let contentSpacing: CGFloat = .space24
    static let horizontalPadding: CGFloat = .space24
}

/// Full-screen stand-in for a file the app has no viewer for (`FileItem.isUnsupportedForPreview`)
/// a font, a disk image, a `.webm` AVFoundation can't decode. Mirrors the Files app: the
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

    private var typeText: String {
        item.kind.isEmpty ? L10n.UnsupportedPreview.genericType : item.kind.uppercased()
    }

    var body: some View {
        NavigationStack {
            content
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

    private var content: some View {
        #if os(macOS)
            // Finder's look for a file Quick Look can't show: its real icon, name and details,
            // then the apps that can open it.
            ContentUnavailableView {
                Label {
                    Text(item.name)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: item.kind) ?? .data))
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.iconSize, height: Constants.iconSize)
                }
            } description: {
                Text(verbatim: [typeText, FileSizeFormat.string(item.size)].joined(separator: " · "))
                    + Text(verbatim: "\n")
                    + Text(L10n.UnsupportedPreview.cannotOpen)
            } actions: {
                MacOpenWithButtons(source: systemShare)
            }
        #else
            VStack(spacing: Constants.contentSpacing) {
                Spacer()

                VStack(spacing: Constants.headerSpacing) {
                    FileTypeIcon(kind: item.kind)
                        .frame(width: Constants.iconSize, height: Constants.iconSize)

                    Text(item.name)
                        .type(.headline3, style: .primaryOnSurface)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(typeText)
                        .type(.body2(.regular), style: .secondary)
                    Text(FileSizeFormat.string(item.size))
                        .type(.body2(.regular), style: .secondary)
                }

                Text(L10n.UnsupportedPreview.cannotOpen)
                    .type(.body2(.regular), style: .secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Constants.horizontalPadding)
            .backgroundGradient()
        #endif
    }
}

#Preview {
    UnsupportedFilePreviewView(
        item: FileItem(name: "test_X24504889T2", path: "", dateModified: Date(), size: 6_144, kind: "dat"),
        systemShare: .unavailable,
        onDismiss: {}
    )
}

#Preview("Remote file") {
    UnsupportedFilePreviewView(
        item: FileItem(name: "invite.ics", path: "Documents", dateModified: Date(), size: 2_048, kind: "ics"),
        systemShare: .remote(
            FileItem(name: "invite.ics", path: "Documents", dateModified: Date(), size: 2_048, kind: "ics"),
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        ),
        onDismiss: {},
        onShareLink: {},
        onRename: {},
        onDownload: {},
        onDelete: {}
    )
}
