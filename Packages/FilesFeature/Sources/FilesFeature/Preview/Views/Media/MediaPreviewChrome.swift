import CoreModels
import SwiftUI

struct MediaPreviewChrome<Content: View>: View {
    let item: FileItem
    let serverURL: URL
    let isEmbedded: Bool
    var hasOpenWithPage = false
    let onDismiss: () -> Void
    var onShare: (() -> Void)?
    var onRename: (() -> Void)?
    var onDownload: (() -> Void)?
    var onDelete: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack {
                content
                    .previewChrome(
                        title: item.name,
                        systemShare: .remote(item, serverURL: serverURL),
                        onShareLink: onShare,
                        onRename: onRename,
                        onDownload: onDownload,
                        onDelete: onDelete,
                        file: item,
                        hasOpenWithPage: hasOpenWithPage,
                        onClose: onDismiss
                    )
            }
        }
    }
}

#Preview {
    MediaPreviewChrome(
        item: FileItem(name: "clip.webm", path: "", dateModified: .distantPast, size: 3_667_214, kind: "webm"),
        serverURL: URL(fileURLWithPath: "/"),
        isEmbedded: false,
        onDismiss: {}
    ) {
        Color.black
    }
}
