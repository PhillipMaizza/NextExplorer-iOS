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
        /// The dragged row itself, so another Browse window, which does not list it, can move it.
        var item: FileItem?

        static var transferRepresentation: some TransferRepresentation {
            CodableRepresentation(contentType: .nextExplorerItem)
        }
    }

    /// What a folder row of the table takes: rows of this app (moved inside it) or files from
    /// Finder (uploaded into it).
    enum MacRowDrop: Transferable {
        case item(ServerItemReference)
        case file(URL)

        static var transferRepresentation: some TransferRepresentation {
            ProxyRepresentation(importing: { (reference: ServerItemReference) in MacRowDrop.item(reference) })
            ProxyRepresentation(importing: { (url: URL) in MacRowDrop.file(url) })
        }

        var fileURL: URL? {
            guard case let .file(url) = self, url.isFileURL else { return nil }
            return url
        }

        /// A row dragged from this app that carried its item.
        var item: FileItem? {
            guard case let .item(reference) = self else { return nil }
            return reference.item
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
                reference: ServerItemReference(id: item.id, item: item),
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

    /// Accepts files dropped from Finder and hands them to the regular upload flow, and rows
    /// dragged in from another Browse window, which move here. Outlines the folder while a drop
    /// hovers over it.
    struct MacFinderDrop: ViewModifier {
        let isEnabled: Bool
        let onDrop: ([URL]) -> Void
        var onDropItems: ([FileItem]) -> Void = { _ in }

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            content
                .dropDestination(for: MacRowDrop.self) { drops, _ in
                    let files = drops.compactMap(\.fileURL)
                    let items = drops.compactMap(\.item)
                    guard isEnabled, !files.isEmpty || !items.isEmpty else { return false }
                    if !files.isEmpty {
                        onDrop(files)
                    }
                    if !items.isEmpty {
                        onDropItems(items)
                    }
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

    #Preview {
        let folder = FileItem(name: "Projects", path: "", dateModified: Date(), size: 0, kind: "directory")
        let file = FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 1_024, kind: "pdf")
        return List {
            Label { Text(folder.name) } icon: { IconKit.folderFill }
                .modifier(MacFolderDropTarget(folder: folder, isEnabled: true) { _ in })
            Label { Text(file.name) } icon: { IconKit.document }
                .modifier(MacFileDrag(item: file, serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"), isEnabled: true))
        }
        .previewCanvas(.control)
    }
#endif
