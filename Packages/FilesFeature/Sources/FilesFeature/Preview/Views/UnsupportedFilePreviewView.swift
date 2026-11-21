import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .size64
}

/// Full screen stand in for a file the app has no viewer for (`FileItem.isUnsupportedForPreview`)
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
                    file: item,
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
                    Image(nsImage: MacFileTypeIcon.image(forFileName: item.name))
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.iconSize, height: Constants.iconSize)
                }
            } description: {
                Text(verbatim: L10n.UnsupportedPreview.macDescription(
                    item.previewTypeText, FileSizeFormat.string(item.size), L10n.UnsupportedPreview.cannotOpen
                ))
            } actions: {
                MacOpenWithButtons(source: systemShare)
            }
            // Fills the sheet: without it the sheet centers a content sized view, leaving empty
            // bands above the bar and below the content.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.backgroundPrimary.ignoresSafeArea())
        #else
            FileSummaryView(item: item, message: L10n.UnsupportedPreview.cannotOpen)
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
