#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import SwiftUI

    /// Lets a row or cell be dragged: onto a folder in the app to move it (the whole selection
    /// travels along), or out to the Files app, where the download only starts on the drop.
    struct IOSItemDrag: ViewModifier {
        let item: FileItem
        let serverURL: URL
        let selection: () -> [FileItem]

        @Dependency(\.filesClient) private var filesClient

        func body(content: Content) -> some View {
            let builder = DraggedServerItemBuilder(item: item, serverURL: serverURL, filesClient: filesClient, selection: selection)
            return content.draggable(builder.build())
        }
    }

    /// A folder row or cell that takes rows (moved inside) and files (uploaded into it), and
    /// outlines itself while a drop hovers over it.
    struct IOSFolderDropTarget: ViewModifier {
        let folder: FileItem
        let isEnabled: Bool
        let onDrop: ([BrowseDrop]) -> Bool

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            if isEnabled, folder.isDirectory {
                content
                    .dropDestination(for: BrowseDrop.self) { drops, _ in onDrop(drops) } isTargeted: { isTargeted = $0 }
                    .overlay {
                        if isTargeted {
                            RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                                .strokeBorder(Color.accent, lineWidth: Metrics.folderOutlineWidth)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                content
            }
        }
    }

    /// The folder on screen takes files from the Files app and Photos, and rows dragged in from
    /// another window.
    struct IOSFolderBackgroundDrop: ViewModifier {
        let isEnabled: Bool
        let onDrop: ([BrowseDrop]) -> Bool

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            content
                .dropDestination(for: BrowseDrop.self) { drops, _ in
                    isEnabled && onDrop(drops)
                } isTargeted: { isTargeted = isEnabled && $0 }
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous)
                            .strokeBorder(Color.accent, lineWidth: Metrics.dropOutlineWidth)
                            .padding(Metrics.dropOutlineInset)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    /// Both halves on one row: it can be dragged, and (when a folder) dropped onto.
    struct IOSRowDragDrop: ViewModifier {
        let item: FileItem
        let serverURL: URL
        let canDropHere: Bool
        let selection: () -> [FileItem]
        let onDrop: ([BrowseDrop]) -> Bool

        func body(content: Content) -> some View {
            content
                .modifier(IOSItemDrag(item: item, serverURL: serverURL, selection: selection))
                .modifier(IOSFolderDropTarget(folder: item, isEnabled: canDropHere, onDrop: onDrop))
        }
    }

    private enum Metrics {
        static let dropOutlineWidth: CGFloat = 3
        static let dropOutlineInset: CGFloat = .space8
        static let folderOutlineWidth: CGFloat = 2
    }

    #Preview {
        let folder = FileItem(name: "Projects", path: "", dateModified: Date(), size: 0, kind: "directory")
        let file = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 1_024, kind: "pdf")
        let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        return List {
            Label { Text(folder.name) } icon: { IconKit.folderFill }
                .modifier(IOSRowDragDrop(item: folder, serverURL: serverURL, canDropHere: true, selection: { [] }, onDrop: { _ in true }))
            Label { Text(file.name) } icon: { IconKit.document }
                .modifier(IOSRowDragDrop(item: file, serverURL: serverURL, canDropHere: true, selection: { [] }, onDrop: { _ in true }))
        }
        .modifier(IOSFolderBackgroundDrop(isEnabled: true, onDrop: { _ in true }))
    }
#endif
