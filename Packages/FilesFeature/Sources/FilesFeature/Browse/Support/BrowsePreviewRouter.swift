import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Routes one preview target `FileItem` to its full screen cover. On iPhone and iPad that is the
/// gallery, which pages through every file in the folder, or the text editor while editing. A Mac
/// shows one file at a time by its `PreviewKind` (unsupported screen, player, archive browser, image
/// gallery, document, editor) and steps through the folder with the arrow keys. The share sheet
/// target is view local to `BrowseContentView`, so it's handed back through `onShareTarget`.
struct BrowsePreviewRouter: View {
    let store: StoreOf<BrowseFeature>
    let item: FileItem
    let onShareTarget: (FileItem) -> Void
    /// Reports the file the gallery swiped to, so the cover's `.zoom` source follows the current
    /// page. The editor previews a single file.
    var onGalleryItemChange: (FileItem) -> Void = { _ in }

    #if os(macOS)
        @FocusState private var isFocused: Bool
    #endif

    var body: some View {
        #if os(macOS)
            // Like Quick Look, the arrow keys step through the folder's files. Each step rebuilds
            // the preview for the new file, so the image gallery starts on it too.
            routed
                .id(item.id)
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onAppear { isFocused = true }
                .onKeyPress(.leftArrow) { step(by: -1) }
                .onKeyPress(.rightArrow) { step(by: 1) }
                .environment(\.previewOffline, offlineAction(for: item))
        #else
            routed
                .environment(\.previewOffline, offlineAction(for: item))
                .offlineRemovalAlert(
                    store.offlineRemoval,
                    onConfirm: { store.send(.offlineRemovalConfirmed, animation: DSMotion.listDiff) },
                    onCancel: { store.send(.offlineRemovalCancelled) }
                )
        #endif
    }

    private func offlineAction(for item: FileItem) -> PreviewOfflineAction? {
        // A pinned file can always be taken off the device, even before its folder's access loads.
        let isPinned = store.offlinePinnedItemIDs.contains(item.id)
        guard isPinned || (store.access?.canDownload ?? false) else { return nil }
        let isOn = store.offlineItemIDs.contains(item.id)
        return PreviewOfflineAction(
            isOn: isOn,
            toggle: { store.send(.offlineToggleTapped(item)) }
        )
    }

    #if os(macOS)
        private func step(by offset: Int) -> KeyPress.Result {
            let files = store.displayedItems.filter { !$0.isDirectory }
            guard let index = files.firstIndex(where: { $0.id == item.id }),
                  files.indices.contains(index + offset) else { return .ignored }
            store.send(.rowTapped(files[index + offset]))
            return .handled
        }
    #endif

    /// The bars' actions on a file, each only when the folder allows it.
    private var actions: FileGalleryActions {
        let access = store.access
        return FileGalleryActions(
            onShare: (access?.canShare ?? false) ? { onShareTarget($0) } : nil,
            onRename: (access?.canWrite ?? false) ? { store.send(.renameTapped($0)) } : nil,
            onDownload: (access?.canDownload ?? false) ? { store.send(.downloadTapped($0)) } : nil,
            offline: { offlineAction(for: $0) },
            onDelete: (access?.canDelete ?? false) ? { store.send(.deleteTapped($0)) } : nil,
            onInfo: { store.send(.infoTapped($0)) },
            // Same gates as the list's menu: a move deletes the original, a copy is checked on paste.
            onMove: (access?.canWrite ?? false) && (access?.canDelete ?? false)
                ? { store.send(.moveTapped($0), animation: DSMotion.listDiff) }
                : nil,
            onCopy: { store.send(.copyTapped($0), animation: DSMotion.listDiff) },
            onEdit: { store.send(.previewEditTapped($0)) }
        )
    }

    #if os(macOS)
        /// One of `actions` bound to the file this preview shows.
        private func bound(_ action: ((FileItem) -> Void)?) -> (() -> Void)? {
            action.map { action in { action(item) } }
        }
    #endif

    @ViewBuilder
    private var routed: some View {
        #if os(iOS)
            // Every file opens in the gallery and pages through the folder; only
            // editing a text file (or a file New File just made) shows the editor.
            if store.shouldShowTextEditor {
                textEditor
            } else {
                FileGalleryView(
                    items: store.state.galleryItems(startingAt: item),
                    initialItem: item,
                    serverURL: store.serverURL,
                    preload: GalleryPreload(itemID: item.id, fileURL: store.previewFileURL, text: store.textContent),
                    actions: actions,
                    onDismiss: { store.send(.previewDismissed) },
                    onCurrentItemChange: onGalleryItemChange
                )
            }
        #else
            macRouted
        #endif
    }

    #if os(macOS)
        @ViewBuilder
        private var macRouted: some View {
            let actions = actions
            switch store.shouldShowTextEditor ? .text : PreviewKind(item) {
            case .unsupported:
                UnsupportedFilePreviewView(
                    item: item,
                    systemShare: .remote(item, serverURL: store.serverURL),
                    onDismiss: { store.send(.previewDismissed) },
                    onShareLink: bound(actions.onShare),
                    onRename: bound(actions.onRename),
                    onDownload: bound(actions.onDownload),
                    onDelete: bound(actions.onDelete)
                )
            case .media:
                MediaPreview(
                    item: item,
                    serverURL: store.serverURL,
                    onDismiss: { store.send(.previewDismissed) },
                    onShare: bound(actions.onShare),
                    onRename: bound(actions.onRename),
                    onDownload: bound(actions.onDownload),
                    onDelete: bound(actions.onDelete)
                )
            case .archive:
                EmptyView()
            case .image:
                FileGalleryView(
                    items: store.displayedItems.filter { PreviewKind($0) == .image },
                    initialItem: item,
                    serverURL: store.serverURL,
                    actions: actions,
                    onDismiss: { store.send(.previewDismissed) },
                    onCurrentItemChange: onGalleryItemChange
                )
            case .document:
                FilePreviewContainerView(
                    fileURL: store.previewFileURL,
                    errorMessage: store.previewErrorMessage,
                    onDismiss: { store.send(.previewDismissed) },
                    onShareLink: bound(actions.onShare),
                    onRename: bound(actions.onRename),
                    onDownload: bound(actions.onDownload),
                    onDelete: bound(actions.onDelete)
                )
            case .text:
                textEditor
            }
        }
    #endif

    private var textEditor: some View {
        TextFilePreviewView(
            item: item,
            serverURL: store.serverURL,
            fileName: item.name,
            kind: item.kind,
            content: store.textContent,
            errorMessage: store.textEditorErrorMessage,
            isLoading: store.isLoadingTextContent,
            isSaving: store.isSavingTextContent,
            onSave: { store.send(.textSaveTapped($0)) },
            onRetry: { store.send(.textContentRetryTapped) },
            // Opened from the gallery's Edit, closing goes back to the gallery on this file.
            onDismiss: { store.send(store.isPreviewEditing ? .previewEditorClosed : .previewDismissed) },
            shouldStartEditing: store.newlyCreatedFileID == item.id || store.isPreviewEditing
        )
        .dsAlert(isPresented: Binding(get: { store.isTextSaveConflictPresented }, set: { _ in })) {
            DSAlertSheet(
                icon: IconKit.warning,
                title: L10n.TextPreview.conflictTitle(item.name),
                message: L10n.TextPreview.conflictMessage,
                confirmTitle: L10n.TextPreview.conflictOverwrite,
                dismissTitle: L10n.Common.cancel,
                neutralTitle: L10n.TextPreview.conflictReload,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.textSaveOverwriteTapped) },
                onNeutral: { store.send(.textSaveReloadTapped) },
                onDismiss: { store.send(.textSaveConflictDismissed) }
            )
        }
    }
}

#Preview("Text save conflict alert") {
    let item = FileItem(name: "notes.txt", path: "Docs", dateModified: .distantPast, size: 12, kind: "txt")
    var state = BrowseFeature.State(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"), directoryPath: "Docs",
        title: "Docs"
    )
    state.previewItem = item
    state.textContent = "Hello"
    state.textPhase = .loaded
    state.textSaveConflict = BrowseFeature.State.TextSaveConflict(pendingText: "Hello, edited")
    return BrowsePreviewRouter(
        store: Store(initialState: state) { BrowseFeature() },
        item: item,
        onShareTarget: { _ in }
    )
}
