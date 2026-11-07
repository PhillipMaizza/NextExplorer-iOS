#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import SwiftUI

    /// Drag a row (the whole selection when it is part of one) onto a folder here, or out to the
    /// Files app, and let folder rows and cells take drops. A drop goes through the same reducer
    /// actions as the Mac table, which refuse the folder itself and its descendants and send name
    /// clashes through the transfer conflict prompt.
    struct IOSBrowseItemDragDrop: ViewModifier {
        let store: StoreOf<BrowseFeature>
        let item: FileItem

        func body(content: Content) -> some View {
            content.modifier(IOSRowDragDrop(
                item: item,
                serverURL: store.serverURL,
                scope: store.cacheScope,
                canDropHere: !store.isSelecting,
                canMove: store.canMoveHere,
                canUpload: store.canUploadHere,
                selection: { store.isSelecting ? store.selectedItems : [] },
                onDrop: { IOSBrowseDropSender.send($0, onto: item, store: store) }
            ))
        }
    }

    /// The folder on screen as a drop target, and the owner of the record of the rows being dragged
    /// that every row below it reads.
    struct IOSBrowseBackgroundDragDrop: ViewModifier {
        let store: StoreOf<BrowseFeature>

        @State private var activeDrag = IOSActiveDrag()

        func body(content: Content) -> some View {
            content
                .modifier(IOSFolderBackgroundDrop(
                    destination: store.directoryPath,
                    isEnabled: !store.isSelecting,
                    canMove: store.canMoveHere,
                    canUpload: store.canUploadHere,
                    onDrop: { IOSBrowseDropSender.send($0, onto: nil, store: store) }
                ))
                .environment(\.iosActiveDrag, activeDrag)
        }
    }

    /// Resolves a drop against the store's folder, sends what it comes to, and deletes the staged
    /// copies of files nothing took over.
    enum IOSBrowseDropSender {
        static func send(_ drops: [BrowseDrop], onto folder: FileItem?, store: StoreOf<BrowseFeature>) -> Bool {
            let resolution = BrowseDropHandler.resolve(
                drops: drops,
                folder: folder,
                listed: store.items.map(\.id),
                directoryPath: store.directoryPath,
                receiver: .current(serverURL: store.serverURL, scope: store.cacheScope),
                canMove: store.canMoveHere,
                canUpload: store.canUploadHere
            )
            BrowseDropHandler.discard(resolution.discardedFiles)
            for action in resolution.actions {
                store.send(action)
            }
            return !resolution.actions.isEmpty
        }
    }

    extension BrowseFeature.State {
        var canMoveHere: Bool {
            access?.canDelete ?? false
        }

        /// Allowed while access is still loading, as the `+` upload menu is.
        var canUploadHere: Bool {
            access?.canUpload ?? true
        }

        var selectedItems: [FileItem] {
            items.filter { selectedItemIDs.contains($0.id) }
        }
    }
#endif
