import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let width: CGFloat = 240
}

/// What a long press lifts above an item's menu: the item's thumbnail (or its icon) at a size
/// that can be seen, with its name, as the Files and Photos apps show.
struct FileContextMenuPreview: View {
    let item: FileItem
    let serverURL: URL
    let showThumbnails: Bool

    var body: some View {
        GridCellView(item: item, serverURL: serverURL, showThumbnails: showThumbnails)
            .padding(.space16)
            .frame(width: Constants.width)
            .background(Color.backgroundSecondary)
    }
}

#Preview("File") {
    FileContextMenuPreview(
        item: FileItem(name: "report.pdf", path: "Documents", dateModified: .distantPast, size: 1, kind: "pdf"),
        serverURL: URL(fileURLWithPath: "/"),
        showThumbnails: false
    )
}

#Preview("Folder") {
    FileContextMenuPreview(
        item: FileItem(
            name: "Photos",
            path: "",
            dateModified: .distantPast,
            size: 0,
            kind: FileItem.directoryKind
        ),
        serverURL: URL(fileURLWithPath: "/"),
        showThumbnails: false
    )
}
