#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import SwiftUI

    /// The rows this window is dragging, recorded when a drag starts, so a folder can tell a drag of
    /// its own rows (which may not be dropped on themselves) from files and rows of other windows.
    /// It is not cleared when a drag is cancelled, so it can name rows that are no longer dragged;
    /// that only ever hides the outline of a folder, never changes what a drop does.
    final class IOSActiveDrag: Sendable {
        let rows = LockIsolated<[FileItem]>([])
    }

    private struct ActiveDragKey: EnvironmentKey {
        static let defaultValue: IOSActiveDrag? = nil
    }

    extension EnvironmentValues {
        var iosActiveDrag: IOSActiveDrag? {
            get { self[ActiveDragKey.self] }
            set { self[ActiveDragKey.self] = newValue }
        }
    }

    /// Lets a row or cell be dragged: onto a folder in the app to move it (the whole selection
    /// travels along), or out to the Files app, where the download only starts on the drop.
    struct IOSItemDrag: ViewModifier {
        let item: FileItem
        let serverURL: URL
        let scope: String
        let selection: () -> [FileItem]

        @Dependency(\.filesClient) private var filesClient
        @Environment(\.iosActiveDrag) private var activeDrag

        func body(content: Content) -> some View {
            let builder = DraggedServerItemBuilder(
                item: item, serverURL: serverURL, scope: scope, filesClient: filesClient, selection: selection
            )
            let activeDrag = activeDrag
            return content.draggable({ () -> DraggedServerItem in
                let payload = builder.build()
                activeDrag?.rows.setValue(payload.reference.items)
                return payload
            }())
        }
    }

    /// A folder row or cell that takes rows (moved inside) and files (uploaded into it), and
    /// outlines itself while a drop that it would take hovers over it.
    struct IOSFolderDropTarget: ViewModifier {
        let folder: FileItem
        let isEnabled: Bool
        let canMove: Bool
        let canUpload: Bool
        let onDrop: ([BrowseDrop]) -> Bool

        @State private var isTargeted = false
        @Environment(\.iosActiveDrag) private var activeDrag

        private func canAccept() -> Bool {
            BrowseDropAcceptance.canAccept(
                destination: folder.id,
                isFolder: folder.isDirectory,
                draggedRows: activeDrag?.rows.value ?? [],
                canMove: canMove,
                canUpload: canUpload
            )
        }

        func body(content: Content) -> some View {
            if isEnabled, folder.isDirectory, canMove || canUpload {
                content
                    .dropDestination(for: BrowseDrop.self) { drops, _ in
                        activeDrag?.rows.setValue([])
                        return onDrop(drops)
                    } isTargeted: { isTargeted = $0 && canAccept() }
                    .overlay {
                        if isTargeted {
                            DropOutline(cornerRadius: .radiusSmall, width: Metrics.folderOutlineWidth, inset: 0)
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
        let destination: String
        let isEnabled: Bool
        let canMove: Bool
        let canUpload: Bool
        let onDrop: ([BrowseDrop]) -> Bool

        @State private var isTargeted = false
        @Environment(\.iosActiveDrag) private var activeDrag

        private func canAccept() -> Bool {
            BrowseDropAcceptance.canAccept(
                destination: destination,
                isFolder: true,
                draggedRows: activeDrag?.rows.value ?? [],
                canMove: canMove,
                canUpload: canUpload
            )
        }

        func body(content: Content) -> some View {
            if isEnabled, canMove || canUpload {
                content
                    .dropDestination(for: BrowseDrop.self) { drops, _ in
                        activeDrag?.rows.setValue([])
                        return onDrop(drops)
                    } isTargeted: { isTargeted = $0 && canAccept() }
                    .overlay {
                        if isTargeted {
                            DropOutline(
                                cornerRadius: .radiusLarge,
                                width: Metrics.dropOutlineWidth,
                                inset: Metrics.dropOutlineInset
                            )
                        }
                    }
            } else {
                content
            }
        }
    }

    /// The accent outline a folder or the folder on screen shows while a drop it takes hovers over it.
    struct DropOutline: View {
        let cornerRadius: CGFloat
        let width: CGFloat
        let inset: CGFloat

        var body: some View {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.accent, lineWidth: width)
                .padding(inset)
                .allowsHitTesting(false)
        }
    }

    /// Both halves on one row: it can be dragged, and (when a folder) dropped onto.
    struct IOSRowDragDrop: ViewModifier {
        let item: FileItem
        let serverURL: URL
        let scope: String
        let canDropHere: Bool
        let canMove: Bool
        let canUpload: Bool
        let selection: () -> [FileItem]
        let onDrop: ([BrowseDrop]) -> Bool

        func body(content: Content) -> some View {
            content
                .modifier(IOSItemDrag(item: item, serverURL: serverURL, scope: scope, selection: selection))
                .modifier(IOSFolderDropTarget(
                    folder: item, isEnabled: canDropHere, canMove: canMove, canUpload: canUpload, onDrop: onDrop
                ))
        }
    }

    private enum Metrics {
        static let dropOutlineWidth: CGFloat = 3
        static let dropOutlineInset: CGFloat = .space8
        static let folderOutlineWidth: CGFloat = 2
        static let previewHeight: CGFloat = 160
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        static let scope = "preview"
        static let folder = FileItem(name: "Projects", path: "", dateModified: .distantPast, size: 0, kind: "directory")
        static let file = FileItem(name: "report.pdf", path: "", dateModified: .distantPast, size: 1_024, kind: "pdf")
    }

    @MainActor
    private func previewRow(_ item: FileItem, canMove: Bool, canUpload: Bool) -> some View {
        Label { Text(item.name) } icon: { item.isDirectory ? IconKit.folderFill : IconKit.document }
            .modifier(IOSRowDragDrop(
                item: item, serverURL: PreviewFixture.serverURL, scope: PreviewFixture.scope,
                canDropHere: true, canMove: canMove, canUpload: canUpload, selection: { [] }, onDrop: { _ in true }
            ))
    }

    #Preview("Rows") {
        List {
            previewRow(PreviewFixture.folder, canMove: true, canUpload: true)
            previewRow(PreviewFixture.file, canMove: true, canUpload: true)
        }
        .modifier(IOSFolderBackgroundDrop(
            destination: "Docs",
            isEnabled: true,
            canMove: true,
            canUpload: true,
            onDrop: { _ in true }
        ))
    }

    #Preview("No rights") {
        List {
            previewRow(PreviewFixture.folder, canMove: false, canUpload: false)
        }
        .modifier(IOSFolderBackgroundDrop(
            destination: "Docs",
            isEnabled: true,
            canMove: false,
            canUpload: false,
            onDrop: { _ in true }
        ))
    }

    #Preview("Targeted outline") {
        Label { Text(PreviewFixture.folder.name) } icon: { IconKit.folderFill }
            .padding()
            .overlay { DropOutline(cornerRadius: .radiusSmall, width: Metrics.folderOutlineWidth, inset: 0) }
    }

    #Preview("Background targeted outline") {
        Color.clear
            .frame(height: Metrics.previewHeight)
            .overlay { DropOutline(
                cornerRadius: .radiusLarge,
                width: Metrics.dropOutlineWidth,
                inset: Metrics.dropOutlineInset
            ) }
    }
#endif
