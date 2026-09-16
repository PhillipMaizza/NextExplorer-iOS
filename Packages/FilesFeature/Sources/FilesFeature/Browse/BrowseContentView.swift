import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import PhotosUI
import SwiftUI

private enum BrowseViewMode: String {
    case list, grid
}

private enum Constants {
    /// Lifts a preview cover's toast clear of the `previewChrome` bottom action bar.
    static let previewToolbarToastInset: CGFloat = .size56
    static let emptyStateSpacing: CGFloat = .space8
    static let emptyStateIconSize: CGFloat = .superIcon
    static let gridSpacing: CGFloat = .space16
    /// Inset between a grid tile's content and its `backgroundSecondary` card edge.
    static let gridCellPadding: CGFloat = .space12
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
    static let overlayCrossfadeDuration: Double = 0.2
    /// Skeleton to loaded content crossfade — a touch longer than the overlay swap so the
    /// placeholder visibly resolves into the real rows rather than blinking out.
    static let contentRevealDuration: Double = 0.3
    /// Height of the invisible long-press paste target past the last row.
    static let pasteTargetMinHeight: CGFloat = 260
    /// Gap between the empty folder message and its upload call to action.
    static let emptyUploadButtonTopSpacing: CGFloat = .space24
    static let emptyUploadButtonHPadding: CGFloat = .space24
    /// Keeps the empty folder's dashed upload button from spanning an iPad's full width.
    static let emptyUploadButtonMaxWidth: CGFloat = 360
    /// Placeholder date/size for a search hit's thumbnail item — a search result carries neither,
    /// and fixed values keep its thumbnail cache key steady across renders.
    static let searchThumbnailPlaceholderDate = Date(timeIntervalSince1970: 0)
    static let searchThumbnailPlaceholderSize: Int64 = 0
}

/// The list body shown at every depth of Browse: root and every pushed subfolder
/// render this same view, scoped to their own `BrowseFeature` store. The list/grid
/// choice is a per-device display preference, not per-folder state, so it's stored
/// directly here rather than threaded through `BrowseFeature.State`.
struct BrowseContentView: View {
    @Bindable var store: StoreOf<BrowseFeature>
    @AppStorage(AppStorageKeys.browseViewMode) private var viewModeRaw = BrowseViewMode.list.rawValue
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue
    @AppStorage(AppStorageKeys.removeArchiveAfterDownload) private var removeArchiveAfterDownload = false
    @AppStorage(AppStorageKeys.keepClipboardAfterCopy) private var keepClipboardAfterCopy = false
    @State private var isSortSheetPresented = false
    @State private var toastMessage: DSToastMessage?
    /// The item whose "Create Share Link" sheet is open (from the context menu or the
    /// selection toolbar). Local view state, not routed through `BrowseFeature` — the sheet
    /// owns its own ad-hoc `CreateShareLinkFeature` store.
    @State private var shareTarget: FileItem?
    /// Flipped once a pull-to-refresh completes, purely as a `.hapticFeedback` trigger — the
    /// value itself is meaningless, only the fact that it just changed matters.
    @State private var didFinishRefreshing = false
    @State private var isFilesPickerPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isCameraDeniedAlertPresented = false
    @State private var photosSelection: [PhotosPickerItem] = []
    /// Pairs each file cell/row with the full-screen preview cover so it opens and
    /// interactively swipes-to-dismiss with the native `.zoom` morph (Twitter/Photos style),
    /// instead of a hand-rolled drag gesture.
    @Namespace private var previewTransition
    /// The image the gallery is currently showing (it swipes between siblings). Drives the
    /// cover's `.zoom` source and scrolls the matching cell into view, so dismissing after a
    /// swipe morphs back to the visible image instead of the one first tapped. `nil` until the
    /// gallery reports a page, then the tapped item's id is used.
    @State private var galleryCurrentItemID: String?
    @Shared(.inMemory(UploadBarChrome.visibilityKey)) private var isUploadBarVisible = false
    @Shared(.inMemory(UploadBarChrome.heightKey)) private var uploadBarHeight = UploadBarChrome.fallbackHeight

    private var viewMode: BrowseViewMode {
        BrowseViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var thumbnailSize: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    /// The root's title is re-derived from `L10n` here rather than read from `store.title` (which
    /// captured it once at login) so it re-localizes live when the language changes. Pushed
    /// subfolders show their real folder name from `store.title`.
    private var displayTitle: String {
        store.directoryPath.isEmpty ? L10n.Browse.navigationTitle : store.title
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize.gridItemMinWidth), spacing: Constants.gridSpacing)]
    }

    private func handleTap(_ item: FileItem) {
        // A second tap while the row spinner is up cancels the in-flight open (a slow fetch
        // has no other way out — the cover isn't presented yet).
        if isOpening(item) {
            store.send(.previewDismissed)
            return
        }
        store.send(.rowTapped(item))
    }

    /// Search results only report `dir`/`file` for kind, so derive a real extension from the
    /// file name for the row icon — the same thing `searchResultTapped` hands the preview.
    private func searchResultKind(_ result: SearchResultItem) -> String {
        result.isDirectory ? result.kind : (result.name as NSString).pathExtension.lowercased()
    }

    var body: some View {
        browsingContent
            .sheet(item: $store.scope(state: \.destinationPicker, action: \.destinationPicker)) { pickerStore in
                DestinationPickerView(store: pickerStore)
            }
            .sheet(item: $store.scope(state: \.uploadReview, action: \.uploadReview)) { reviewStore in
                UploadReviewView(store: reviewStore)
            }
            .sheet(item: infoPhaseBinding) { phase in
                infoSheetContent(for: phase)
            }
            .sheet(item: $store.scope(state: \.permissions, action: \.permissions)) { permissionsStore in
                PermissionsSheet(store: permissionsStore)
            }
            .fullScreenCover(isPresented: previewPresentedBinding) {
                // `isPresented`, not `item:` — so an in-place rename (which changes the item's
                // id) updates the cover's content instead of dismissing and re-presenting it.
                if let item = store.previewItem {
                    PreviewZoomContainer(sourceID: galleryCurrentItemID ?? item.id, namespace: previewTransition) {
                        BrowsePreviewRouter(
                            store: store,
                            item: item,
                            removeArchiveAfterDownload: removeArchiveAfterDownload,
                            onShareTarget: { shareTarget = $0 },
                            onGalleryItemChange: { galleryCurrentItemID = $0.id }
                        )
                    }
                    .sheet(isPresented: isDeletingFromPreviewBinding) {
                        deleteConfirmationSheet(dismissingPreview: true)
                    }
                    .sheet(item: renameItemFromPreviewBinding) { renameTarget in
                        renameSheet(renameTarget)
                    }
                    .sheet(item: shareTargetFromPreviewBinding) { shareItem in
                        createShareLinkSheet(for: shareItem, fromPreview: true)
                    }
                    .hapticFeedback(.warning, trigger: store.deleteConfirmationItem)
                    // The preview stays put through downloads and renames: their result
                    // toasts surface over the cover, and "Open" on a download routes back
                    // through the reducer so the cover dismisses before the tab switches.
                    .dsToast(previewToastBinding, extraBottomInset: Constants.previewToolbarToastInset)
                    .dsToast(previewProgressToastBinding, extraBottomInset: Constants.previewToolbarToastInset)
                }
            }
            .sheet(item: shareTargetBinding) { item in
                createShareLinkSheet(for: item, fromPreview: false)
            }
            .dsToast(listToastBinding, extraBottomInset: bottomChromeClearance)
            .dsToast(listProgressToastBinding, extraBottomInset: bottomChromeClearance)
            // `fileActionErrorMessage` (rename/delete/extract/compress failures) was set on
            // `State` but never actually read by any view — silently swallowed. Mirrored into
            // the same toast the unsupported-file-type warning uses.
            .onChange(of: store.fileActionErrorMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = DSToastMessage(icon: IconKit.warning, text: newValue)
            }
            .onChange(of: store.downloadSuccessMessage) { _, newValue in
                guard let newValue else { return }
                let inPreview = store.previewItem != nil
                toastMessage = .success(newValue, actionTitle: L10n.Browse.open) {
                    // From a preview, close the cover first, then switch tabs after a settle.
                    store.send(inPreview ? .openDownloadsFromPreview : .delegate(.openDownloadsTapped))
                }
            }
            .onChange(of: store.transferSuccessMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(newValue)
            }
            .onChange(of: store.clipboardStagedMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(newValue)
            }
            .onChange(of: store.transferErrorMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .failure(newValue, actionTitle: L10n.Common.retry) {
                    store.send(.retryTransferTapped, animation: .default)
                }
            }
            // The share target is view-local state; clear it whenever the preview closes so a
            // stale value can't auto-reopen the share sheet over the next preview.
            .onChange(of: store.previewItem == nil) { _, previewClosed in
                if previewClosed {
                    shareTarget = nil
                    // Cleared after the dismiss morph has already captured the source id.
                    galleryCurrentItemID = nil
                }
            }
            .task {
                store.send(.onAppear)
            }
    }

    /// Split out of `body`: with every modifier below chained directly onto the file-action
    /// sheets/covers added above, the compiler couldn't type-check the whole expression in
    /// reasonable time.
    private var browsingContent: some View {
        Group {
            if isInitialLoad {
                BrowseSkeletonView(
                    isGridView: viewMode == .grid,
                    gridColumns: gridColumns,
                    iconSize: thumbnailSize.iconSize
                )
                .transition(.opacity)
            } else if viewMode == .list {
                listContent
                    .transition(.opacity)
            } else {
                gridContent
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: Constants.contentRevealDuration), value: isInitialLoad)
        .tint(Color.accent)
        .refreshable {
            await store.send(.refreshButtonTapped).finish()
            didFinishRefreshing.toggle()
        }
        .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.phase.errorMessage == nil }
        .hapticFeedback(.error, trigger: store.phase.errorMessage) { _, newValue in newValue != nil }
        .syncCompletedToast(trigger: didFinishRefreshing, isErrorFree: store.phase.errorMessage == nil, extraBottomInset: bottomChromeClearance)
        .overlay {
            overlayStateContent
                .id(overlayState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Scoped to the overlay so an implicit animation can't catch sibling geometry
                // settling on first appear (same fix as `SharedView`).
                .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayState)
        }
        .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: store.dataSource)
        .safeAreaInset(edge: .top, spacing: 0) {
            PinnedTitleSearchHeader(
                title: store.isSelecting ? L10n.Common.selectedCount(store.selectedItemIDs.count) : displayTitle,
                searchText: $store.searchQuery.sending(\.searchQueryChanged)
            ) {
                if store.isSearching {
                    DSSegmentedControl(
                        options: BrowseFeature.SearchScope.allCases,
                        selection: $store.searchScope.sending(\.searchScopeChanged),
                        label: { $0.title }
                    )
                    if !store.availableSearchCategories.isEmpty {
                        SearchFilterChips(
                            availableCategories: store.availableSearchCategories,
                            selectedCategories: store.selectedSearchCategories,
                            onToggle: { store.send(.searchCategoryToggled($0)) },
                            onSelectAll: { store.send(.searchFilterCleared) }
                        )
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            selectSortToolbar(
                isSelecting: store.isSelecting,
                isAllSelected: isAllSelected,
                isSelectAvailable: !store.isSearching && store.hasDisplayedItems,
                isGridView: viewMode == .grid,
                onSelectModeToggled: { store.send(.selectModeToggled) },
                onSelectAllToggled: { store.send(isAllSelected ? .deselectAllTapped : .selectAllTapped) },
                onCancel: { store.send(.selectModeToggled) },
                onToggleViewMode: {
                    withAnimation {
                        viewModeRaw = (viewMode == .list ? BrowseViewMode.grid : .list).rawValue
                    }
                },
                clipboardMenu: {
                    if store.clipboard != nil, !store.directoryPath.isEmpty {
                        Section {
                            Button {
                                store.send(.pasteTapped(keepItemsAfterCopy: keepClipboardAfterCopy), animation: .default)
                            } label: {
                                Label { Text(pasteActionTitle) } icon: { IconKit.paste }
                            }
                            .disabled(!canPasteIntoCurrentFolder)
                            Button {
                                store.send(.clipboardCleared, animation: .default)
                            } label: {
                                Label { Text(L10n.Browse.actionClearClipboard) } icon: { IconKit.close }
                            }
                        }
                    }
                }
            ) {
                Button {
                    isSortSheetPresented = true
                } label: {
                    Label { Text(L10n.Common.sort) } icon: { IconKit.sort }
                }
            }
            if !store.isSelecting, canUploadHere {
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    UploadSourceMenu(
                        label: {
                            IconKit.plus
                                .foregroundStyle(Color.primaryDS)
                        },
                        leadingActions: {
                            if !store.directoryPath.isEmpty {
                                Button { store.send(.newFolderTapped) } label: {
                                    Label { Text(L10n.Browse.actionNewFolder) } icon: { IconKit.folder }
                                }
                            }
                        },
                        isFilesPickerPresented: $isFilesPickerPresented,
                        isPhotosPickerPresented: $isPhotosPickerPresented,
                        isCameraPresented: $isCameraPresented,
                        isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
                    )
                    .accessibilityLabel(L10n.Uploads.menuTitle)
                }
            }
        }
        .modifier(UploadPickers(
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented,
            photosSelection: $photosSelection,
            onDocumentsPicked: { urls in
                guard !urls.isEmpty else { return }
                store.send(.beginUpload(.documents(urls)))
            },
            onPhotosPicked: { items in
                guard !items.isEmpty else { return }
                store.send(.beginUpload(.photos(items)))
                photosSelection = []
            },
            onCameraCaptured: { url in
                store.send(.beginUpload(.camera(url)))
            }
        ))
        .hapticFeedback(.selection, trigger: viewModeRaw)
        .hapticFeedback(.selection, trigger: store.isSelecting)
        .toolbar(store.isSelecting ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            if store.isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                if let singleSelectedItem, store.access?.canWrite ?? false {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.rename) {
                            store.send(.renameTapped(singleSelectedItem))
                        }
                    }
                }
                if let singleSelectedItem, store.access?.canShare ?? false {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.shareLink) {
                            shareTarget = singleSelectedItem
                        }
                    }
                }
                if isFavoriteActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: isEntireSelectionAlreadyFavorited ? IconKit.starFill : IconKit.star) {
                            store.send(.bulkFavoriteTapped)
                        }
                    }
                }
                if isTransferActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.copy) {
                            store.send(.bulkCopyTapped, animation: .default)
                        }
                    }
                }
                if isTransferActionVisible, store.access?.canWrite ?? false, store.access?.canDelete ?? false {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.move) {
                            store.send(.bulkMoveTapped, animation: .default)
                        }
                    }
                }
                if isDownloadActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.download) {
                            store.send(.bulkDownloadTapped(.documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                        }
                    }
                }
                if isDeleteActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.delete, role: .destructive, tint: .negative) {
                            store.send(.bulkDeleteTapped)
                        }
                    }
                }
            }
        }
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.selectedItemIDs
        )
        .sheet(isPresented: bulkDeleteConfirmationBinding) {
            DSAlertSheet(
                icon: IconKit.delete,
                title: bulkDeleteConfirmationTitle,
                message: deleteConfirmationMessage,
                confirmTitle: L10n.Common.delete,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.bulkDeleteConfirmed) },
                onDismiss: { store.send(.bulkDeleteCancelled) }
            )
        }
        .hapticFeedback(.warning, trigger: store.bulkDeleteConfirmationIsPresented)
        .sheet(isPresented: $isSortSheetPresented) {
            SortSheet(
                options: BrowseFeature.SortOption.allCases,
                directions: BrowseFeature.SortDirection.allCases,
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                optionIcon: { $0.icon },
                optionTitle: { $0.title },
                directionIcon: { $0.icon },
                directionTitle: { $0.title },
                onSelectOption: { store.send(.sortOptionChanged($0)) },
                onSelectDirection: { store.send(.sortDirectionChanged($0)) },
                onDismiss: { isSortSheetPresented = false }
            )
        }
        .sheet(item: renameItemBinding) { item in
            renameSheet(item)
        }
        .sheet(isPresented: newFolderSheetBinding) {
            NameInputSheet(
                icon: IconKit.folder,
                title: L10n.Browse.newFolderTitle,
                placeholder: L10n.Browse.newFolderPlaceholder,
                confirmTitle: L10n.Browse.newFolderConfirm,
                isBusy: store.isPerformingFileAction,
                onConfirm: { store.send(.newFolderConfirmed($0)) },
                onCancel: { store.send(.newFolderCancelled) }
            )
        }
        .sheet(isPresented: isDeletingBinding) {
            deleteConfirmationSheet(dismissingPreview: false)
        }
        .hapticFeedback(.warning, trigger: store.deleteConfirmationItem)
        .sheet(isPresented: transferConflictBinding) {
            DSAlertSheet(
                icon: IconKit.warning,
                title: L10n.Browse.transferConflictTitle,
                message: transferConflictMessage,
                confirmTitle: L10n.Browse.transferConflictReplace,
                dismissTitle: L10n.Common.cancel,
                neutralTitle: L10n.Browse.transferConflictKeepBoth,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.transferConflictResolved(.replace), animation: .default) },
                onNeutral: { store.send(.transferConflictResolved(.keepBoth), animation: .default) },
                onDismiss: { store.send(.transferConflictResolved(nil)) }
            )
        }
        .hapticFeedback(.warning, trigger: store.transferConflict)
    }

    private var previewPresentedBinding: Binding<Bool> {
        Binding(
            get: { store.previewItem != nil && isPreviewContentReady },
            set: {
                if !$0 {
                    store.send(.previewDismissed)
                }
            }
        )
    }

    /// Whether the tapped file has loaded enough to present its cover. The download/editor
    /// previews (PDF, office docs, text) hold the cover — and show a row spinner — until their
    /// fetch lands; gallery, streaming, archives and the unsupported screen are ready at once.
    /// Branch order mirrors `previewContent(for:)`.
    private var isPreviewContentReady: Bool {
        guard let item = store.previewItem else { return false }
        if item.isUnsupportedForPreview {
            return true
        }
        if item.isStreamableMedia {
            return true
        }
        if item.isBrowsableArchive {
            return true
        }
        if (item.isImage || item.isRawImage) && !item.isSVG {
            return true
        }
        if item.isPreviewableViaDownload {
            return store.previewFileURL != nil || store.previewErrorMessage != nil
        }
        return store.textContent != nil || store.textEditorErrorMessage != nil
    }

    private func isOpening(_ item: FileItem) -> Bool {
        isOpeningID(item.id)
    }

    private func isOpeningID(_ id: String) -> Bool {
        store.previewItem?.id == id && !isPreviewContentReady
    }

    /// Search hits and browse rows share an `id` scheme (`path/name`), so `searchResultTapped`
    /// builds a `FileItem` whose id matches the hit — the `.zoom` source and the opening
    /// spinner can key off the same value.
    private func searchResultCell(row: SearchResultItem, grid: Bool) -> some View {
        Group {
            if grid {
                GridCellView(
                    name: row.name, isDirectory: row.isDirectory,
                    isFavorite: store.favoritePaths.contains(row.id), kind: searchResultKind(row),
                    thumbnailFile: searchResultThumbnailFile(row),
                    serverURL: store.serverURL,
                    showThumbnails: store.preferences.showThumbnails,
                    iconSize: thumbnailSize.iconSize,
                    matchedSource: PreviewMatchedSource(id: row.id, namespace: previewTransition),
                    isOpening: isOpeningID(row.id)
                )
            } else {
                FileRowView(
                    name: row.name, isDirectory: row.isDirectory, subtitle: searchResultSnippet(row),
                    lineLabel: searchResultLineLabel(row),
                    isFavorite: store.favoritePaths.contains(row.id), kind: searchResultKind(row),
                    thumbnailFile: searchResultThumbnailFile(row),
                    serverURL: store.serverURL,
                    showThumbnails: store.preferences.showThumbnails,
                    matchedSource: PreviewMatchedSource(id: row.id, namespace: previewTransition),
                    isOpening: isOpeningID(row.id)
                )
            }
        }
    }

    /// A thumbnail-capable `FileItem` for a file search hit; `nil` for a directory, which keeps
    /// its folder glyph. Search hits carry no size or modified date, so use stable placeholders
    /// to hold the thumbnail cache key steady across renders. `supportsThumbnail` is set for the
    /// kinds the server will thumbnail (images, RAW, video); a PDF renders its first page on
    /// device off its kind alone, matching a browse row.
    private func searchResultThumbnailFile(_ result: SearchResultItem) -> FileItem? {
        guard !result.isDirectory else { return nil }
        let kind = searchResultKind(result)
        let serverThumbnailable = FileItem.isImageKind(kind) || FileItem.isRawImageKind(kind) || FileItem.isVideoKind(kind)
        return FileItem(
            name: result.name,
            path: result.path,
            dateModified: Constants.searchThumbnailPlaceholderDate,
            size: Constants.searchThumbnailPlaceholderSize,
            kind: kind,
            supportsThumbnail: serverThumbnailable
        )
    }

    /// Extracted from the grid/list `ForEach` bodies — inlining the full cell (with the
    /// `matchedSource` / `isOpening` args) tipped those already-large expressions past the
    /// type-checker's budget.
    private func gridCell(for item: FileItem) -> some View {
        GridCellView(
            item: item,
            isFavorite: store.favoritePaths.contains(item.id),
            serverURL: store.serverURL,
            showThumbnails: store.preferences.showThumbnails,
            iconSize: thumbnailSize.iconSize,
            matchedSource: PreviewMatchedSource(id: item.id, namespace: previewTransition),
            isOpening: isOpening(item)
        )
    }

    private func listRowCell(for item: FileItem) -> some View {
        FileRowView(
            item: item,
            isFavorite: store.favoritePaths.contains(item.id),
            serverURL: store.serverURL,
            showThumbnails: store.preferences.showThumbnails,
            matchedSource: PreviewMatchedSource(id: item.id, namespace: previewTransition),
            isOpening: isOpening(item)
        )
    }

    /// Toasts split by surface: while a preview cover is up, its toasts render over the cover,
    /// otherwise over the list. One `toastMessage`/`fileActionProgressMessage` still drives
    /// both — only the visible one is bound.
    private var listToastBinding: Binding<DSToastMessage?> {
        Binding(get: { store.previewItem == nil ? toastMessage : nil }, set: { toastMessage = $0 })
    }

    private var previewToastBinding: Binding<DSToastMessage?> {
        Binding(get: { store.previewItem != nil ? toastMessage : nil }, set: { toastMessage = $0 })
    }

    /// Read-only from the store's perspective: `fileActionProgressMessage` clears itself once
    /// the extract/compress effect resolves, so there's nothing for the view to write back —
    /// the toast has no auto-dismiss timer to fire early either (`DSToastMessage.progress`
    /// sets `isPersistent`), so the setter is genuinely never called in practice.
    private var listProgressToastBinding: Binding<DSToastMessage?> {
        Binding(
            get: { store.previewItem == nil ? store.fileActionProgressMessage.map(DSToastMessage.progress) : nil },
            set: { _ in }
        )
    }

    private var previewProgressToastBinding: Binding<DSToastMessage?> {
        Binding(
            get: { store.previewItem != nil ? store.fileActionProgressMessage.map(DSToastMessage.progress) : nil },
            set: { _ in }
        )
    }

    private var shareTargetBinding: Binding<FileItem?> {
        Binding(get: { store.previewItem == nil ? shareTarget : nil }, set: { shareTarget = $0 })
    }

    private var shareTargetFromPreviewBinding: Binding<FileItem?> {
        Binding(get: { store.previewItem != nil ? shareTarget : nil }, set: { shareTarget = $0 })
    }

    private func createShareLinkSheet(for item: FileItem, fromPreview: Bool) -> some View {
        CreateShareLinkSheet(
            store: Store(
                initialState: CreateShareLinkFeature.State(
                    serverURL: store.serverURL,
                    itemName: item.name,
                    itemPath: item.path,
                    isDirectory: item.isDirectory
                )
            ) {
                CreateShareLinkFeature()
            },
            onViewShares: { store.send(fromPreview ? .goToSharedTabFromPreview : .delegate(.goToSharedTab)) }
        )
    }

    /// Distinct identities for "still loading" vs. "have a result", so swapping between the
    /// two (once the fetch resolves) is a genuinely fresh sheet presentation rather than an
    /// in-place content change — see `FileInfoLoadingSheet`'s doc comment for why that
    /// matters for getting the right height.
    private enum InfoSheetPhase: Identifiable, Equatable {
        case loading(FileItem)
        case result(FileItem)

        var id: String {
            switch self {
            case let .loading(item): "loading-\(item.id)"
            case let .result(item): "result-\(item.id)"
            }
        }
    }

    private var infoPhase: InfoSheetPhase? {
        guard let item = store.infoItem else { return nil }
        guard store.infoMetadata != nil || store.infoErrorMessage != nil else {
            return .loading(item)
        }
        return .result(item)
    }

    private var infoPhaseBinding: Binding<InfoSheetPhase?> {
        Binding(
            get: { infoPhase },
            set: {
                if $0 == nil {
                    store.send(.infoDismissed)
                }
            }
        )
    }

    @ViewBuilder
    private func infoSheetContent(for phase: InfoSheetPhase) -> some View {
        switch phase {
        case let .loading(item):
            FileInfoLoadingSheet(item: item, onDismiss: { store.send(.infoDismissed) })
        case let .result(item):
            FileInfoSheet(
                item: item,
                metadata: store.infoMetadata,
                usage: store.infoUsage,
                errorMessage: store.infoErrorMessage,
                onDismiss: { store.send(.infoDismissed) }
            )
        }
    }

    /// Drives the rename `NameInputSheet`; a swipe down dismiss routes back through the reducer
    /// so `renameSheetItem` clears. The reducer also nils it itself on a completed rename.
    /// Split like the delete confirmation so it presents over whichever surface is frontmost.
    private var renameItemBinding: Binding<FileItem?> {
        Binding(
            get: { store.previewItem == nil ? store.renameSheetItem : nil },
            set: {
                if $0 == nil {
                    store.send(.renameCancelled)
                }
            }
        )
    }

    private var renameItemFromPreviewBinding: Binding<FileItem?> {
        Binding(
            get: { store.previewItem != nil ? store.renameSheetItem : nil },
            set: {
                if $0 == nil {
                    store.send(.renameCancelled)
                }
            }
        )
    }

    private func renameSheet(_ item: FileItem) -> some View {
        NameInputSheet(
            icon: IconKit.rename,
            title: L10n.Browse.renameTitle,
            placeholder: L10n.Browse.renameNamePlaceholder,
            confirmTitle: L10n.Common.save,
            initialName: item.name,
            isBusy: store.isPerformingFileAction,
            onConfirm: { store.send(.renameConfirmed($0)) },
            onCancel: { store.send(.renameCancelled) }
        )
    }

    private var newFolderSheetBinding: Binding<Bool> {
        Binding(
            get: { store.isNewFolderSheetPresented },
            set: {
                if !$0 {
                    store.send(.newFolderCancelled)
                }
            }
        )
    }

    /// No op setter: the sheet is dismiss disabled and only closes through one of
    /// `DSAlertSheet`'s own buttons, which drive the reducer directly. Split in two so the
    /// confirmation presents over whichever surface is frontmost: the list, or a preview cover.
    private var isDeletingBinding: Binding<Bool> {
        Binding(get: { store.deleteConfirmationItem != nil && store.previewItem == nil }, set: { _ in })
    }

    private var isDeletingFromPreviewBinding: Binding<Bool> {
        Binding(get: { store.deleteConfirmationItem != nil && store.previewItem != nil }, set: { _ in })
    }

    /// The gallery holds many images, so deleting one drops it from the pager and stays open
    /// (like Photos) rather than tearing the whole cover down.
    private var isPreviewGallery: Bool {
        store.previewItem.map { ($0.isImage || $0.isRawImage) && !$0.isSVG } ?? false
    }

    private func deleteConfirmationSheet(dismissingPreview: Bool) -> some View {
        DSAlertSheet(
            icon: IconKit.delete,
            title: deleteConfirmationTitle,
            message: deleteConfirmationMessage,
            confirmTitle: L10n.Common.delete,
            dismissTitle: L10n.Common.cancel,
            role: .destructive,
            closeAccessibilityLabel: L10n.Common.close,
            onConfirm: {
                // A single-item preview dismisses the cover and defers the delete so the row
                // animates out on the list. The gallery (and the list) delete in place. Either
                // way `deleteConfirmationItem` clears synchronously, so no binding flicker.
                if dismissingPreview, !isPreviewGallery {
                    store.send(.deleteConfirmedFromPreview)
                } else {
                    store.send(.deleteConfirmed)
                }
            },
            onDismiss: { store.send(.deleteCancelled) }
        )
    }

    private var deleteConfirmationTitle: String {
        guard let item = store.deleteConfirmationItem else { return L10n.Browse.deleteConfirmTitle }
        return L10n.Browse.deleteConfirmOne(item.name)
    }

    /// `deleteMessage` plus, once `delete-impact` answers, a line about the share links the
    /// delete would break. Shared by the single- and bulk-delete alerts since only one is
    /// ever up. A still-running or failed check adds nothing / a soft note respectively.
    private var deleteConfirmationMessage: String {
        let base = L10n.Browse.deleteMessage
        switch store.deleteImpactCheck {
        case let .loaded(impact) where impact.shareCount == 1:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesOne
        case let .loaded(impact) where impact.shareCount > 1:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesMany(impact.shareCount)
        case .unavailable:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesUnavailable
        case .idle, .checking, .loaded:
            return base
        }
    }

    /// The button closures own dismissal (they clear `transferConflict`); the no op setter
    /// keeps a SwiftUI initiated dismiss from firing a second resolve into a torn down sheet.
    private var transferConflictBinding: Binding<Bool> {
        Binding(get: { store.transferConflict != nil }, set: { _ in })
    }

    private var transferConflictMessage: String {
        guard let conflict = store.transferConflict else { return "" }
        return conflict.count == 1
            ? L10n.Browse.transferConflictMessageOne(conflict.firstName)
            : L10n.Browse.transferConflictMessageMany(conflict.count)
    }

    private var isAllSelected: Bool {
        store.hasDisplayedItems && store.selectedItemIDs.count == store.displayedItemCount
    }

    /// Rename only makes sense for a single target — `nil` (hiding the toolbar icon) for
    /// zero or multiple selected items.
    private var singleSelectedItem: FileItem? {
        guard store.selectedItemIDs.count == 1, let id = store.selectedItemIDs.first else { return nil }
        return store.items[id: id]
    }

    /// Only directories can be favorited, so a selection mixing a file in with a folder has
    /// no well-defined bulk target — the icon disappears entirely rather than silently
    /// ignoring the file, which a merely-disabled icon would leave ambiguous.
    private var isFavoriteActionVisible: Bool {
        !store.selectedItemIDs.isEmpty && store.selectedItemIDs.allSatisfy { id in
            store.items[id: id]?.isDirectory ?? false
        }
    }

    /// Filled when tapping the toolbar star would unfavorite the whole selection, matching
    /// the single-item context-menu icon's own filled/outline convention.
    private var isEntireSelectionAlreadyFavorited: Bool {
        !store.selectedItemIDs.isEmpty && store.selectedItemIDs.allSatisfy(store.favoritePaths.contains)
    }

    private var isDownloadActionVisible: Bool {
        !store.selectedItemIDs.isEmpty && (store.access?.canDownload ?? false)
    }

    private var isDeleteActionVisible: Bool {
        !store.selectedItemIDs.isEmpty && (store.access?.canDelete ?? false)
    }

    /// Copy/Move from the selection toolbar — available whenever anything is selected, except
    /// for a lone root location (same rule the single-item context menu enforces via
    /// `isSoleRootLocation`). Copy needs no permission; the Move button adds a
    /// `canWrite && canDelete` gate at its site.
    private var isTransferActionVisible: Bool {
        !store.selectedItemIDs.isEmpty && !(store.directoryPath.isEmpty && store.items.count <= 1)
    }

    /// A multi-select bottom-toolbar button, every glyph pinned to the same square so the
    /// row reads as uniform regardless of each symbol's intrinsic aspect ratio. Defaults to
    /// `primaryDS`; only Delete passes an explicit `.negative` tint.
    private func selectionToolbarButton(
        icon: Image,
        role: ButtonRole? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        SelectionToolbarButton(icon: icon, role: role, tint: tint, action: action)
    }

    private var bulkDeleteConfirmationBinding: Binding<Bool> {
        Binding(get: { store.bulkDeleteConfirmationIsPresented }, set: { _ in })
    }

    private var bulkDeleteConfirmationTitle: String {
        L10n.Browse.deleteConfirmMany(store.selectedItemIDs.count)
    }

    private func fileActionsMenu(for item: FileItem) -> some View {
        FileActionsMenu(
            store: store,
            item: item,
            removeArchiveAfterDownload: removeArchiveAfterDownload,
            onShare: { shareTarget = $0 }
        )
    }

    /// Which branch of `overlayStateContent` is currently showing — a plain discriminant so
    /// the overlay can cross-fade between states instead of hard-cutting between them.
    private enum OverlayState: Hashable {
        case none, error, empty, searching, noResults
    }

    /// A fetch with nothing yet to show: the first load of this folder (including the frame
    /// before `onAppear` starts it) or a retry after a failed first load. Drives the loading
    /// skeleton and suppresses the empty state so a fresh folder never flashes "folder is
    /// empty" for a frame.
    private var isInitialLoad: Bool {
        !store.phase.hasLoaded && store.items.isEmpty && store.phase.errorMessage == nil
    }

    private var overlayState: OverlayState {
        if store.phase.errorMessage != nil {
            .error
        } else if store.phase.hasLoaded, !store.isSearching, !store.hasDisplayedItems {
            .empty
        } else if store.isSearching, store.isSearchingRemotely, store.displayedSearchResults?.isEmpty ?? true {
            // A recursive backend search is in flight with nothing to show yet (the client
            // pre-fill found no local matches) — spin rather than flash "no results".
            .searching
        } else if store.isSearching, let results = store.displayedSearchResults, results.isEmpty {
            .noResults
        } else {
            .none
        }
    }

    @ViewBuilder
    private var overlayStateContent: some View {
        switch overlayState {
        case .searching:
            DSSpinner()
                .transition(.opacity)
        case .error:
            if let errorMessage = store.phase.errorMessage {
                EmptyStateView(
                    icon: IconKit.warning,
                    message: errorMessage
                ) {
                    store.send(.refreshButtonTapped)
                }
                .transition(.opacity)
            }
        case .empty:
            VStack(spacing: Constants.emptyUploadButtonTopSpacing) {
                EmptyStateView(icon: IconKit.folder, message: L10n.EmptyState.folderEmpty)
                if !store.isSelecting, canUploadHere {
                    emptyStateUploadButton
                }
            }
            .transition(.opacity)
        case .noResults:
            noResultsState
                .transition(.opacity)
        case .none:
            EmptyView()
        }
    }

    private var listContent: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    if store.isSearching {
                        searchResultRows
                    } else {
                        folderItemRows
                    }
                }
                offlineFooterRow
                pasteTargetRow
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            // Scrolling the results dismisses the search keyboard, the expected gesture when the
            // results fill the screen and tapping a row would navigate rather than just defocus.
            .scrollDismissesKeyboard(.immediately)
            .backgroundGradient()
            .safeAreaPadding(.bottom, bottomChromeClearance)
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: store.displayedItems
            )
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: store.displayedSearchResults
            )
            .scrollGalleryPageIntoView(proxy, id: galleryCurrentItemID)
        }
    }

    private var gridContent: some View {
        // Bind once: `store.displayedItems` filters + localized sorts on every read, and this
        // builder would otherwise hit it for the ForEach and the animation value separately.
        let displayedItems = store.displayedItems
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: Constants.gridSpacing) {
                    if store.isSearching {
                        ForEach(store.displayedSearchResults ?? []) { result in
                            Button {
                                store.send(.searchResultTapped(result))
                            } label: {
                                searchResultCell(row: result, grid: true)
                                    .dsCard(padding: Constants.gridCellPadding)
                            }
                            .buttonStyle(DSHapticButtonStyle())
                        }
                    } else {
                        ForEach(displayedItems) { item in
                            Button {
                                if store.isSelecting {
                                    store.send(.itemSelectionToggled(item.id))
                                } else {
                                    handleTap(item)
                                }
                            } label: {
                                gridCell(for: item)
                                    .dsCard(padding: Constants.gridCellPadding)
                                    .overlay(alignment: .topLeading) {
                                        if store.isSelecting {
                                            DSSelectionIndicator(isSelected: store.selectedItemIDs.contains(item.id))
                                        }
                                    }
                            }
                            .buttonStyle(DSHapticButtonStyle())
                            .hapticFeedback(.selection, trigger: store.selectedItemIDs.contains(item.id))
                            .contextMenu {
                                if !store.isSelecting {
                                    fileActionsMenu(for: item)
                                }
                            }
                        }
                    }
                }
                .padding(Constants.gridSpacing)
                .animation(
                    .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                    value: displayedItems
                )
                .animation(
                    .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                    value: store.displayedSearchResults
                )
                offlineFooter
                pasteTargetArea
            }
            .scrollDismissesKeyboard(.immediately)
            .backgroundGradient()
            .safeAreaPadding(.bottom, bottomChromeClearance)
            .dismissKeyboardOnTap()
            .scrollGalleryPageIntoView(proxy, id: galleryCurrentItemID)
        }
    }

    /// Invisible long-press target filling the space past the last row — a plain
    /// `.contextMenu` on the whole list/scroll container lifts a snapshot of the entire list
    /// on long-press, which reads as the list jumping. Scoping it to this transparent trailing
    /// area keeps the list itself still. Present only while something is staged, so an empty
    /// menu never opens.
    @ViewBuilder
    private var pasteTargetRow: some View {
        if store.clipboard != nil, !store.directoryPath.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: Constants.pasteTargetMinHeight)
                .contentShape(Rectangle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contextMenu { pasteEmptySpaceMenu }
        }
    }

    /// "Showing a saved copy" notice, rendered as a footer below the last row/cell of the
    /// list/grid (not a blocking overlay) whenever the listing on screen came from the offline
    /// cache. Scrolls with the content, so a reachable listing shows nothing extra.
    @ViewBuilder
    private var offlineFooter: some View {
        if case let .cached(fetchedAt) = store.dataSource {
            DSInfoCard(L10n.Browse.offlineBannerDetail(OfflineRelativeTime.string(from: fetchedAt)))
                .padding(.horizontal, .space16)
                .padding(.top, .space12)
        }
    }

    /// `offlineFooter` as a plain, separatorless `List` row for `listContent`.
    @ViewBuilder
    private var offlineFooterRow: some View {
        if case .cached = store.dataSource {
            offlineFooter
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var pasteTargetArea: some View {
        if store.clipboard != nil, !store.directoryPath.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: Constants.pasteTargetMinHeight)
                .contentShape(Rectangle())
                .contextMenu { pasteEmptySpaceMenu }
        }
    }

    /// Bottom scroll clearance for the chrome floating under this list: the breadcrumb bar
    /// (`BrowseTabView`/`FavoritesView`, pushed screens only — the root's `directoryPath` is
    /// always empty) and the app-level upload progress bar while it's showing. Both are placed
    /// by ancestors a `List` inside a pushed `navigationDestination` doesn't reliably respect.
    private var bottomChromeClearance: CGFloat {
        (store.directoryPath.isEmpty ? 0 : BrowseBreadcrumbBarMetrics.height)
            + (isUploadBarVisible ? uploadBarHeight + UploadBarChrome.gap : 0)
    }

    /// Gates the `+` upload menu on the folder's own `FileAccess.canUpload`. Defaults to
    /// allowed while access is still loading — the first browse response fills it in.
    private var canUploadHere: Bool {
        store.access?.canUpload ?? true
    }

    /// The empty folder's call to action: the same camera / Photos / Files menu as the `+`,
    /// behind an accent pill so a first time user has somewhere obvious to start.
    private var emptyStateUploadButton: some View {
        UploadSourceMenu(
            label: { UploadDashedLabel(title: L10n.Uploads.menuTitle) },
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
        )
        .tint(.primaryDS)
        .frame(maxWidth: Constants.emptyUploadButtonMaxWidth)
        .padding(.horizontal, Constants.emptyUploadButtonHPadding)
        .accessibilityLabel(L10n.Uploads.menuTitle)
    }

    /// Whether the current folder is a legitimate paste target for the staged clipboard —
    /// gates the "Paste" action in the `…` menu.
    private var canPasteIntoCurrentFolder: Bool {
        store.clipboard?.canPaste(into: store.directoryPath, canWrite: store.access?.canWrite ?? false) ?? false
    }

    /// "Paste" for a single staged item, "Paste N items" past that.
    private var pasteActionTitle: String {
        let count = store.clipboard?.items.count ?? 0
        return count <= 1 ? L10n.Browse.actionPaste : L10n.Browse.actionPasteCount(count)
    }

    /// Long-press menu for the empty space in the list/grid — only present while something is
    /// staged, so an empty menu never opens. Mirrors the `…` menu's paste/clear pair.
    @ViewBuilder
    private var pasteEmptySpaceMenu: some View {
        if store.clipboard != nil, !store.directoryPath.isEmpty {
            Button {
                store.send(.pasteTapped(keepItemsAfterCopy: keepClipboardAfterCopy), animation: .default)
            } label: {
                Label { Text(L10n.Browse.actionPasteHere) } icon: { IconKit.paste }
            }
            .disabled(!canPasteIntoCurrentFolder)
            Button {
                store.send(.clipboardCleared, animation: .default)
            } label: {
                Label { Text(L10n.Browse.actionClearClipboard) } icon: { IconKit.close }
            }
        }
    }

    @ViewBuilder
    private var folderItemRows: some View {
        // `store.displayedItems` filters + sorts on every read — bind it once here rather than
        // re-deriving it per row (the separator checks below alone made it O(n^2 log n)).
        let items = store.displayedItems
        let firstItemID = items.first?.id
        let lastItemID = items.last?.id
        ForEach(items) { item in
            Button {
                if store.isSelecting {
                    store.send(.itemSelectionToggled(item.id))
                } else {
                    handleTap(item)
                }
            } label: {
                HStack(spacing: .space12) {
                    if store.isSelecting {
                        DSSelectionIndicator(isSelected: store.selectedItemIDs.contains(item.id))
                    }
                    listRowCell(for: item)
                }
            }
            .buttonStyle(DSHapticButtonStyle())
            .hapticFeedback(.selection, trigger: store.selectedItemIDs.contains(item.id))
            .accessibilityAddTraits(store.isSelecting && store.selectedItemIDs.contains(item.id) ? [.isSelected] : [])
            .contextMenu {
                if !store.isSelecting {
                    fileActionsMenu(for: item)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
            .swipeActions(edge: .trailing) {
                if !store.isSelecting {
                    if store.access?.canDelete ?? false {
                        Button {
                            store.send(.deleteTapped(item))
                        } label: {
                            IconKit.delete
                        }
                        .tint(.negative)
                        .accessibilityLabel(L10n.Common.delete)
                    }
                    // Only folders can be favorited — the server 400s on anything else.
                    if item.isDirectory {
                        Button {
                            store.send(.favoriteToggleButtonTapped(item))
                        } label: {
                            store.favoritePaths.contains(item.id) ? IconKit.starFill : IconKit.star
                        }
                        .tint(.accent)
                        .accessibilityLabel(store.favoritePaths.contains(item.id) ? L10n.Browse.actionRemoveFromFavorites : L10n.Browse.actionAddToFavorites)
                    }
                    if store.access?.canWrite ?? false {
                        Button {
                            store.send(.renameTapped(item))
                        } label: {
                            IconKit.rename
                        }
                        .tint(.positive)
                        .accessibilityLabel(L10n.Browse.actionRename)
                    }
                }
            }
            .listRowSeparator(item.id == firstItemID ? .hidden : .visible, edges: .top)
            .listRowSeparator(item.id == lastItemID ? .hidden : .visible, edges: .bottom)
        }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        let results = store.displayedSearchResults ?? []
        ForEach(results) { result in
            Button {
                store.send(.searchResultTapped(result))
            } label: {
                searchResultCell(row: result, grid: false)
            }
            .buttonStyle(DSHapticButtonStyle())
            .listRowBackground(Color.backgroundSecondary)
            .listRowSeparator(result.id == results.first?.id ? .hidden : .visible, edges: .top)
            .listRowSeparator(result.id == results.last?.id ? .hidden : .visible, edges: .bottom)
        }
    }

    @ViewBuilder
    private var noResultsState: some View {
        VStack(spacing: Constants.emptyStateSpacing) {
            IconKit.search
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.emptyStateIconSize, height: Constants.emptyStateIconSize)
            Text(L10n.Browse.searchNoMatchesInFolder(store.searchQuery))
                .type(.body1(.semibold), style: .secondary)
            if store.searchScope == .thisFolder {
                DSButton(L10n.Browse.searchEverywhere,
                         icon: IconKit.search,
                         style: .secondary,
                         size: .small,
                         isLoading: false, action: {
                             store.send(.searchScopeChanged(.everywhere))
                         })
                         .padding(.top, Constants.emptyStateSpacing)
            }
        }
        .padding(.space16)
        .multilineTextAlignment(.center)
    }
}

@MainActor
private func browsePreview(
    directoryPath: String = "Documents",
    configureClient: (inout FilesClient) -> Void = { _ in },
    mutateState: (inout BrowseFeature.State) -> Void = { _ in }
) -> some View {
    var state = BrowseFeature.State(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        directoryPath: directoryPath,
        title: L10n.Browse.navigationTitle
    )
    mutateState(&state)
    var client = FilesClient.previewValue
    configureClient(&client)
    let store = Store(initialState: state) {
        BrowseFeature()
    } withDependencies: {
        $0.filesClient = client
    }
    return NavigationStack {
        BrowseContentView(store: store)
            .navigationTitle(L10n.Browse.navigationTitle)
    }
}

private let browsePreviewItems: [FileItem] = [
    FileItem(name: "Projects", path: "Documents", dateModified: Date(), size: 0, kind: "directory"),
    FileItem(name: "budget.xlsx", path: "Documents", dateModified: Date(), size: 44_000, kind: "xlsx"),
    FileItem(name: "notes.txt", path: "Documents", dateModified: Date(), size: 1_200, kind: "txt"),
    FileItem(name: "cover.jpg", path: "Documents", dateModified: Date(), size: 2_400_000, kind: "jpg", supportsThumbnail: true),
]

private let browsePreviewEmptyAccess = FileAccess(
    canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
)

#Preview("Browse — content") {
    browsePreview(mutateState: { $0.items = IdentifiedArray(uniqueElements: browsePreviewItems) })
}

#Preview("Browse — loading") {
    browsePreview(mutateState: { $0.phase = .loading })
}

#Preview("Browse — empty folder") {
    browsePreview(
        configureClient: { $0.browse = { _, path in BrowseResult(items: [], access: browsePreviewEmptyAccess, path: path) } }
    )
}

#Preview("Browse — error") {
    browsePreview(mutateState: { $0.phase = .failed(L10n.EmptyState.loadFailed) })
}

#Preview("Browse — no search results") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchResults = []
    })
}

#Preview("Browse — searching everywhere") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchScope = .everywhere
        $0.isSearchingRemotely = true
    })
}

#Preview("Browse — delete alert, linked shares") {
    browsePreview(mutateState: {
        $0.items = IdentifiedArray(uniqueElements: browsePreviewItems)
        $0.deleteConfirmationItem = browsePreviewItems[1]
        $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 2))
    })
}

#Preview("Browse — delete alert, share check unavailable") {
    browsePreview(mutateState: {
        $0.items = IdentifiedArray(uniqueElements: browsePreviewItems)
        $0.deleteConfirmationItem = browsePreviewItems[1]
        $0.deleteImpactCheck = .unavailable
    })
}
