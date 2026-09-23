#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import SwiftUI
    import UniformTypeIdentifiers

    extension UTType {
        /// In app drag payload: which server item is being dragged. Declared in the app's
        /// Info.plist so it never leaves the process as anything Finder would try to keep.
        static let nextExplorerItem = UTType(exportedAs: "com.phillipmaizza.nextexplorer.item")
    }

    struct ServerItemReference: Codable, Transferable {
        let id: String

        static var transferRepresentation: some TransferRepresentation {
            CodableRepresentation(contentType: .nextExplorerItem)
        }
    }

    /// A dragged row. Inside the app it is a reference (drop on a folder to move it); dragged to
    /// Finder a file becomes a file promise: the download only starts once the drop lands, and
    /// the copy keeps its real name. Folders never export as a file.
    struct DraggedServerItem: Transferable {
        let reference: ServerItemReference
        let fileName: String
        let isDirectory: Bool
        let fetch: @Sendable () async throws -> URL

        static var transferRepresentation: some TransferRepresentation {
            ProxyRepresentation(exporting: \.reference)
            FileRepresentation(exportedContentType: .data) { item in
                try await SentTransferredFile(item.fetch())
            }
            .exportingCondition { !$0.isDirectory }
            .suggestedFileName { $0.fileName }
        }
    }

    extension DraggedServerItem {
        init(item: FileItem, serverURL: URL, filesClient: FilesClient) {
            self.init(
                reference: ServerItemReference(id: item.id),
                fileName: item.name,
                isDirectory: item.isDirectory
            ) {
                try await filesClient.downloadRawFile(serverURL, item)
            }
        }
    }

    /// Lets a row be dragged: onto a folder in the app to move it, or out to Finder to save it.
    struct MacFileDrag: ViewModifier {
        let item: FileItem
        let serverURL: URL
        let isEnabled: Bool

        @Dependency(\.filesClient) private var filesClient

        func body(content: Content) -> some View {
            if isEnabled {
                content.draggable(DraggedServerItem(item: item, serverURL: serverURL, filesClient: filesClient))
            } else {
                content
            }
        }
    }

    /// A folder row that accepts other rows dropped onto it, moving them inside.
    struct MacFolderDropTarget: ViewModifier {
        let folder: FileItem
        let isEnabled: Bool
        let onDrop: ([FileItem.ID]) -> Void

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            if isEnabled, folder.isDirectory {
                content
                    .dropDestination(for: ServerItemReference.self) { references, _ in
                        let ids = references.map(\.id).filter { $0 != folder.id }
                        guard !ids.isEmpty else { return false }
                        onDrop(ids)
                        return true
                    } isTargeted: { isTargeted = $0 }
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

    /// Both halves on one row: it can be dragged, and (when a folder) dropped onto.
    struct MacRowDragDrop: ViewModifier {
        let item: FileItem
        let serverURL: URL
        let canDrag: Bool
        let canDropHere: Bool
        let onDrop: ([FileItem.ID]) -> Void

        func body(content: Content) -> some View {
            content
                .modifier(MacFileDrag(item: item, serverURL: serverURL, isEnabled: canDrag))
                .modifier(MacFolderDropTarget(folder: item, isEnabled: canDropHere, onDrop: onDrop))
        }
    }

    /// Accepts files dropped from Finder and hands them to the regular upload flow, outlining the
    /// folder while a drop hovers over it.
    struct MacFinderDrop: ViewModifier {
        let isEnabled: Bool
        let onDrop: ([URL]) -> Void

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            content
                .dropDestination(for: URL.self) { urls, _ in
                    let files = urls.filter(\.isFileURL)
                    guard isEnabled, !files.isEmpty else { return false }
                    onDrop(files)
                    return true
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

    private enum Metrics {
        static let dropOutlineWidth: CGFloat = 3
        static let dropOutlineInset: CGFloat = .space8
        static let folderOutlineWidth: CGFloat = 2
    }
#endif
