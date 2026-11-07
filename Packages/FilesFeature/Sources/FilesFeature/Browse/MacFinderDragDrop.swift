#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import SwiftUI
    import UniformTypeIdentifiers

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

        /// A row dragged from this app that carried its item, when the drag started in `receiver`'s
        /// server and account.
        func item(for receiver: DragOrigin) -> FileItem? {
            guard case let .item(reference) = self, reference.origin == receiver else { return nil }
            return reference.item
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
        let serverURL: URL
        let isEnabled: Bool
        let onDrop: ([FileItem.ID]) -> Void

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            if isEnabled, folder.isDirectory {
                content
                    .dropDestination(for: ServerItemReference.self) { references, _ in
                        let receiver = DragOrigin.current(serverURL: serverURL)
                        let ids = references.filter { $0.origin == receiver }.map(\.id).filter { $0 != folder.id }
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
                .modifier(MacFolderDropTarget(folder: item, serverURL: serverURL, isEnabled: canDropHere, onDrop: onDrop))
        }
    }

    /// Accepts files dropped from Finder and hands them to the regular upload flow, and rows
    /// dragged in from another Browse window, which move here. Outlines the folder while a drop
    /// hovers over it.
    struct MacFinderDrop: ViewModifier {
        let serverURL: URL
        let isEnabled: Bool
        let onDrop: ([URL]) -> Void
        var onDropItems: ([FileItem]) -> Void = { _ in }

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            content
                .dropDestination(for: MacRowDrop.self) { drops, _ in
                    let files = drops.compactMap(\.fileURL)
                    let receiver = DragOrigin.current(serverURL: serverURL)
                    let items = drops.compactMap { $0.item(for: receiver) }
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
                .modifier(MacFolderDropTarget(folder: folder, serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"), isEnabled: true) { _ in })
            Label { Text(file.name) } icon: { IconKit.document }
                .modifier(MacFileDrag(item: file, serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"), isEnabled: true))
        }
        .previewCanvas(.control)
    }
#endif
