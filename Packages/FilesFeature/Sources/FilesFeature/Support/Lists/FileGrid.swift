import AppStorageKeys
import DesignSystem
import SwiftUI

/// A lazy grid of file or folder tiles laid out for the screen: a fixed count per row on a phone,
/// as many as fit on an iPad, and the grid size the user picked (`AppStorageKeys.thumbnailSize`).
struct FileGrid<Content: View>: View {
    let content: FileGridMetrics.Content
    @ViewBuilder let cells: () -> Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue

    init(_ content: FileGridMetrics.Content = .files, @ViewBuilder cells: @escaping () -> Content) {
        self.content = content
        self.cells = cells
    }

    private var isCompact: Bool {
        #if os(iOS)
            horizontalSizeClass != .regular
        #else
            false
        #endif
    }

    var body: some View {
        LazyVGrid(
            columns: FileGridMetrics.columns(
                for: content,
                size: ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium,
                isCompact: isCompact
            ),
            alignment: .leading,
            spacing: content == .files ? FileGridMetrics.rowSpacing : FileGridMetrics.spacing
        ) {
            cells()
        }
        // A new size from the Grid sheet reflows the tiles behind it instead of jumping.
        .animation(DSMotion.listDiff, value: thumbnailSizeRaw)
    }
}

#Preview("Files") {
    ScrollView {
        FileGrid {
            ForEach(0 ..< 9, id: \.self) { index in
                GridCellView(name: "photo-\(index).jpg", isDirectory: false, kind: "jpg")
                    .dsGridTile()
            }
        }
        .padding(FileGridMetrics.margin)
    }
    .backgroundGradient()
}

#Preview("Folders") {
    ScrollView {
        FileGrid(.folders) {
            ForEach(["Documents", "Photos", "Music", "Projects"], id: \.self) { name in
                GridCellView(name: name, isDirectory: true)
                    .dsGridTile()
            }
        }
        .padding(FileGridMetrics.margin)
    }
    .backgroundGradient()
}
