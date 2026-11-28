import CoreModels
import DesignSystem
import Localization
import SwiftUI

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
            MacNoPreviewPage(item: item, source: systemShare)
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
