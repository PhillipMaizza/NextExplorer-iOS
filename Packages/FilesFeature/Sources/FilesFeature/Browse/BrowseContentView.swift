import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Localization
import PhotosUI
import SwiftUI

private enum BrowseViewMode: String {
    /// `table` is the Mac only sortable column view.
    case list, grid, table
}

private enum Constants {
    /// Lifts a preview cover's toast clear of the `previewChrome` bottom action bar.
    static let previewToolbarToastInset: CGFloat = .size56
    static let emptyStateSpacing: CGFloat = .space8
    static let emptyStateIconSize: CGFloat = .superIcon
    /// Height of the invisible long-press paste target past the last row.
    static let pasteTargetMinHeight: CGFloat = 260
    /// Gap between the empty folder message and its upload call to action.
    static let emptyUploadButtonTopSpacing: CGFloat = .space24
    static let emptyUploadButtonHPadding: CGFloat = .space24
    /// Keeps the empty folder's dashed upload button from spanning an iPad's full width.
    static let emptyUploadButtonMaxWidth: CGFloat = 360
}

/// The list body shown at every depth of Browse: root and every pushed subfolder
/// render this same view, scoped to their own `BrowseFeature` store. The list/grid
/// choice is a per-device display preference, not per-folder state, so it's stored
/// directly here rather than threaded through `BrowseFeature.State`.
struct BrowseContentView: View {
    @Bindable var store: StoreOf<BrowseFeature>
    /// Observed only to refresh the offline badges when a download completes.
    @AppStorage(AppStorageKeys.browseViewMode) private var viewModeRaw = BrowseViewMode.list.rawValue
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue
    @AppStorage(AppStorageKeys.keepClipboardAfterCopy) private var shouldKeepClipboardPreference = false
    @State private var isSortSheetPresented = false
    @State private var toastMessage: DSToastMessage?
    /// The item whose "Create Share Link" sheet is open (from the context menu or the
    /// selection toolbar). Local view state, not routed through `BrowseFeature`: the sheet
    /// owns its own ad-hoc `CreateShareLinkFeature` store.
    @State private var shareTarget: FileItem?
    /// Flipped once a pull-to-refresh completes, purely as a `.hapticFeedback` trigger: the
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
    @State private var sourceVisibility = PreviewSourceVisibility()
    /// Whether the open cover zooms, decided once when it appears and held until it closes: the
    /// cover itself takes the list off screen, which must not change the dismiss transition.
    @State private var frozenCoverZoom: Bool?
    /// The image the gallery is currently showing (it swipes between siblings). Drives the
    /// cover's `.zoom` source and scrolls the matching cell into view, so dismissing after a
    /// swipe morphs back to the visible image instead of the one first tapped. `nil` until the
    /// gallery reports a page, then the tapped item's id is used.
    @State private var galleryCurrentItemID: String?
    @Environment(\.isSplitViewDetail) private var isSplitViewDetail
    /// The screen's bottom safe area (the home indicator), part of the path bar's clearance.
    @State private var bottomSafeInset: CGFloat = 0
    /// From the folder picker appearing until its sheet has fully closed.
    @State private var isDestinationPickerOnScreen = false
    @Shared(.inMemory(UploadBarChrome.visibilityKey)) private var isUploadBarVisible = false
    @Shared(.inMemory(UploadBarChrome.heightKey)) private var uploadBarHeight = UploadBarChrome.fallbackHeight

    /// A Mac keeps a copied item on the clipboard after pasting, as Finder does; iOS asks.
    private var shouldKeepClipboardAfterCopy: Bool {
        #if os(macOS)
            true
        #else
            shouldKeepClipboardPreference
        #endif
    }

    private var viewMode: BrowseViewMode {
        #if os(macOS)
            // The Mac always shows the sortable column table.
            return .table
        #else
            let mode = BrowseViewMode(rawValue: viewModeRaw) ?? .list
            return mode == .table ? .list : mode
        #endif
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

    private func handleTap(_ item: FileItem) {
        // A second tap while the row spinner is up cancels the in-flight open (a slow fetch
        // has no other way out: the cover isn't presented yet).
        if isOpening(item) {
            store.send(.previewDismissed)
            return
        }
        store.send(.rowTapped(item))
    }

    var body: some View {
        browsingContent
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafeInset = $0 }
            .sheet(item: destinationPickerBinding(inPreview: false), onDismiss: destinationPickerDismissed) {
                destinationPicker($0)
            }
            .dsSheet(item: $store.scope(state: \.uploadReview, action: \.uploadReview)) { reviewStore in
                UploadReviewView(store: reviewStore)
            }
        #if os(iOS)
            .dsSheet(item: infoPhaseBinding(inPreview: false)) { phase in
                infoSheetContent(for: phase)
            }
        #endif
            .dsSheet(item: $store.scope(state: \.permissions, action: \.permissions)) { permissionsStore in
                PermissionsSheet(store: permissionsStore)
            }
            .fullScreenCover(isPresented: previewPresentedBinding) {
                // `isPresented`, not `item:`; so an in-place rename (which changes the item's
                // id) updates the cover's content instead of dismissing and re-presenting it.
                if let item = store.previewItem {
                    let sourceID = galleryCurrentItemID ?? item.id
                    let zooms = frozenCoverZoom ?? sourceVisibility.canZoom(from: sourceID)
                    PreviewZoomContainer(sourceID: sourceID, namespace: previewTransition, zooms: zooms) {
                        BrowsePreviewRouter(
                            store: store,
                            item: item,
                            onShareTarget: { shareTarget = $0 },
                            onGalleryItemChange: { galleryCurrentItemID = $0.id }
                        )
                    }
                    .dsAlert(isPresented: isDeletingFromPreviewBinding) {
                        deleteConfirmationSheet(dismissingPreview: true)
                    }
                    .dsSheet(item: renameItemFromPreviewBinding) { renameTarget in
                        renameSheet(renameTarget)
                    }
                    .dsSheet(item: shareTargetFromPreviewBinding) { shareItem in
                        createShareLinkSheet(for: shareItem, fromPreview: true)
                    }
                    // Get Info and Move from the gallery's title menu, over the cover.
                    .sheet(item: destinationPickerBinding(inPreview: true), onDismiss: destinationPickerDismissed) {
                        destinationPicker($0)
                    }
                    .dsAlert(isPresented: transferConflictBinding(inPreview: true)) {
                        transferConflictSheet
                    }
                    #if os(iOS)
                    .dsSheet(item: infoPhaseBinding(inPreview: true)) { phase in
                        infoSheetContent(for: phase)
                    }
                    #endif
                    // The preview stays put through downloads and renames: their result
                    // toasts surface over the cover, and "Open" on a download routes back
                    // through the reducer so the cover dismisses before the tab switches.
                    .dsToast(previewToastBinding, extraBottomInset: Constants.previewToolbarToastInset)
                    .dsToast(previewProgressToastBinding, extraBottomInset: Constants.previewToolbarToastInset)
                    .onAppear { frozenCoverZoom = zooms }
                    .onDisappear { frozenCoverZoom = nil }
                }
            }
            .dsSheet(item: shareTargetBinding) { item in
                createShareLinkSheet(for: item, fromPreview: false)
            }
            .dsToast(listToastBinding, extraBottomInset: bottomChromeClearance)
            .dsToast(listProgressToastBinding, extraBottomInset: bottomChromeClearance)
            // `fileActionErrorMessage` (rename/delete/extract/compress failures) was set on
            // `State` but never actually read by any view: silently swallowed. Mirrored into
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
                #if os(iOS)
                    // No ⌘Z at hand on a phone: the toast offers the undo itself.
                    if !store.undoStack.isEmpty {
                        toastMessage = .success(newValue, actionTitle: L10n.Menu.undo) {
                            store.send(.undoTapped, animation: DSMotion.listDiff)
                        }
                        return
                    }
                #endif
                toastMessage = .success(newValue)
            }
            .onChange(of: store.clipboardStagedMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(newValue)
            }
            .onChange(of: store.transferErrorMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .failure(newValue, actionTitle: L10n.Common.retry) {
                    store.send(.retryTransferTapped, animation: DSMotion.listDiff)
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
        #if os(iOS)
            .fileUndoRegistration(store.undoStack) { [store] in
                store.send(.undoTapped, animation: DSMotion.listDiff)
            }
        #endif
            .onAppear { sourceVisibility.isScreenVisible = true }
            .onDisappear {
                sourceVisibility.isScreenVisible = false
                // Leaving mid open (a tab switch or a push while a slow file still loads) cancels
                // it, like a second tap on the spinning row; the cover would otherwise appear over
                // another screen with nothing to zoom from. An open cover also takes this view off
                // screen, but by then its content is ready, so it is left alone.
                if store.previewItem != nil, !store.isPreviewContentReady {
                    // Next tick: a disappear driven by a reducer (a push) must not send reentrantly.
                    Task { @MainActor in store.send(.previewDismissed) }
                }
            }
            .task {
                // Yield first so these sends land after whatever action presented this view has
                // finished reducing, never reentrantly during it (TCA forbids reentrant sends).
                await Task.yield()
                // Gone already (a jump replaced this screen): its element is no longer in the stack.
                guard !Task.isCancelled else { return }
                store.send(.onAppear)
                store.send(.computeOfflineAvailability)
            }
            // New results, or a change in what this folder keeps offline: find the results on the device.
            .task(id: SearchOnDeviceKey(results: store.searchResults?.ids.elements, offline: store.offlineItemIDs)) {
                store.send(.computeSearchOnDevice)
            }
            // A finished offline download can change what's available here, so refresh the badges.
            // The completion mutates shared state, so this `onChange` fires mid reduce; hop to the next
            // tick so the send isn't reentrant.
            .onOfflinePhaseChange { phase in
                if phase == .completed {
                    Task { @MainActor in
                        store.send(.computeOfflineAvailability)
                        store.send(.computeSearchOnDevice)
                    }
                }
            }
        #if os(macOS)
            .modifier(MacBrowseInspector(screen: store) { shareTarget = $0 })
        #endif
    }

    /// Split out of `body`: with every modifier below chained directly onto the file-action
    /// sheets/covers added above, the compiler couldn't type-check the whole expression in
    /// reasonable time.
    /// Placeholder rows, cells or table rows in the current view mode, while a folder's first
    /// listing or a search's first answer is on its way.
    @ViewBuilder
    private var loadingSkeleton: some View {
        if viewMode == .table {
            #if os(macOS)
                MacBrowseTableSkeleton()
            #endif
        } else {
            BrowseSkeletonView(
                isGridView: viewMode == .grid,
                gridColumns: FileGridMetrics.columns,
                iconSize: thumbnailSize.iconSize
            )
        }
    }

    private var browsingContent: some View {
        Group {
            if isInitialLoad {
                loadingSkeleton
                    .transition(.opacity)
            } else if viewMode == .table, !store.isSelecting, !store.isSearching {
                // A table has no footer row, so the saved copy note sits under it.
                VStack(spacing: 0) {
                    tableContent
                    offlineFooter
                }
                .transition(.opacity)
            } else if viewMode == .table, store.isSearching {
                searchTableContent
                    .transition(.opacity)
            } else if viewMode != .grid {
                listContent
                    .transition(.opacity)
            } else {
                gridContent
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DSMotion.contentReveal, value: isInitialLoad)
        .platformAccentTint()
        .refreshable {
            await store.send(.refreshButtonTapped).finish()
            didFinishRefreshing.toggle()
        }
        #if os(macOS)
        .macToolbarRefresh(onRefresh: { await store.send(.refreshButtonTapped).finish() }) {
            didFinishRefreshing.toggle()
        }
        .syncCompletedToast(
            trigger: didFinishRefreshing,
            isErrorFree: store.phase.errorMessage == nil,
            extraBottomInset: bottomChromeClearance
        )
        #endif
        .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.phase.errorMessage == nil }
        .hapticFeedback(.error, trigger: store.phase.errorMessage) { _, newValue in newValue != nil }
        .overlay {
            overlayStateContent
                .id(overlayState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Scoped to the overlay so an implicit animation can't catch sibling geometry
                // settling on first appear (same fix as `SharedView`).
                .animation(DSMotion.stateFade, value: overlayState)
        }
        .animation(DSMotion.stateFade, value: store.dataSource)
        .safeAreaInset(edge: .top, spacing: 0) {
            PinnedTitleSearchHeader(
                title: displayTitle,
                selectionTitle: store.isSelecting ? L10n.Common.selectedCount(store.selectedItemIDs.count) : nil,
                searchText: $store.searchQuery.sending(\.searchQueryChanged),
                shouldFadeIntoContent: viewMode != .table,
                isSearchPending: store.isSearchPending
            ) {
                // The Mac shows these natively, as a scope bar and search field tokens.
                #if os(iOS)
                    if store.isSearching, !store.availableSearchCategories.isEmpty {
                        SearchFilterChips(
                            availableCategories: store.availableSearchCategories,
                            selectedCategories: store.selectedSearchCategories,
                            onToggle: { store.send(.searchCategoryToggled($0)) },
                            onSelectAll: { store.send(.searchFilterCleared) }
                        )
                    }
                #endif
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationHistoryTitle(displayTitle)
        .toolbar {
            // The Mac table selects natively (click, Command and Shift click), so select mode
            // and the view mode control are iOS only.
            selectSortToolbar(
                isSelecting: store.isSelecting,
                isAllSelected: isAllSelected,
                isSelectAvailable: !store.isSearching && store.canSelectItems && viewMode != .table,
                isGridView: viewMode == .grid,
                onSelectModeToggled: { store.send(.selectModeToggled) },
                onSelectAllToggled: { store.send(isAllSelected ? .deselectAllTapped : .selectAllTapped) },
                onCancel: { store.send(.selectModeToggled) },
                onToggleViewMode: {
                    withAnimation(DSMotion.contentReveal) {
                        viewModeRaw = (viewMode == .grid ? BrowseViewMode.list : .grid).rawValue
                    }
                },
                hasClipboardItems: store.clipboard != nil && !store.directoryPath.isEmpty,
                clipboardMenu: {
                    if store.clipboard != nil, !store.directoryPath.isEmpty {
                        Section {
                            Button {
                                store.send(
                                    .pasteTapped(keepItemsAfterCopy: shouldKeepClipboardAfterCopy),
                                    animation: DSMotion.listDiff
                                )
                            } label: {
                                Label { Text(pasteActionTitle) } icon: { IconKit.paste }
                            }
                            .disabled(!canPasteIntoCurrentFolder)
                            Button {
                                store.send(.clipboardCleared, animation: DSMotion.listDiff)
                            } label: {
                                Label { Text(L10n.Browse.actionClearClipboard) } icon: { IconKit.close }
                            }
                        }
                    }
                }
            ) {
                // The Mac table sorts from its column headers, so only the other modes need this.
                if viewMode != .table {
                    Button {
                        isSortSheetPresented = true
                    } label: {
                        Label { Text(L10n.Common.sort) } icon: { IconKit.sort }
                    }
                }
            }
            #if os(iOS)
                if !store.isSelecting, store.canAddHere {
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        uploadMenu {
                            IconKit.plus
                                .foregroundStyle(Color.primaryDS)
                        }
                    }
                }
            #endif
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
        #if os(macOS)
        .modifier(MacFinderDrop(
            serverURL: store.serverURL,
            scope: store.cacheScope,
            isEnabled: store.canUploadHere && !store.isSelecting,
            onDrop: { urls in store.send(.beginUpload(.documents(urls))) },
            onDropItems: { items in
                guard !store.directoryPath.isEmpty else { return }
                store.send(.itemsDroppedFromOtherWindow(items, destination: store.directoryPath))
            }
        ))
        #else
        .modifier(IOSBrowseBackgroundDragDrop(store: store))
        #endif
        .selectModeChrome(isSelecting: store.isSelecting)
        .prefersToolbarItemsInVerticalBar()
        .toolbar {
            if store.isSelecting {
                #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                #endif
                // One menu holds every action, and only once something is picked.
                if !store.selectedItemIDs.isEmpty {
                    ToolbarItem(placement: .selectionBar) {
                        SelectionActionsMenu(
                            availability: store.selectionAvailability,
                            onInfo: { store.send(.infoTapped($0)) },
                            onRename: { store.send(.renameTapped($0)) },
                            onShareLink: { shareTarget = $0 },
                            onShareKept: { store.send(.keptShareTapped(store.selectedItems)) },
                            onCopy: { store.send(.bulkCopyTapped, animation: DSMotion.listDiff) },
                            onMove: { store.send(.bulkMoveTapped, animation: DSMotion.listDiff) },
                            onSave: { store.send(.bulkDownloadTapped) },
                            onOffline: { store.send(.bulkOfflineTapped) },
                            onFavorite: { store.send(.bulkFavoriteTapped) },
                            onDelete: { store.send(.bulkDeleteTapped) }
                        )
                    }
                }
            }
        }
        .dsAlert(isPresented: bulkDeleteConfirmationBinding) {
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
        .dsSheet(isPresented: $isSortSheetPresented) {
            SortSheet(
                options: BrowseFeature.SortOption.allCases,
                directions: BrowseFeature.SortDirection.allCases,
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                optionIcon: { $0.icon },
                optionTitle: { $0.title },
                directionIcon: { $0.icon },
                directionTitle: { $0.title },
                onSelectOption: { store.send(.sortOptionChanged($0), animation: DSMotion.listChange) },
                onSelectDirection: { store.send(.sortDirectionChanged($0), animation: DSMotion.listChange) },
                onDismiss: { isSortSheetPresented = false }
            )
        }
        .dsSheet(item: renameItemBinding) { item in
            renameSheet(item)
        }
        .dsSheet(isPresented: newFolderSheetBinding) {
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
        .dsSheet(isPresented: newFileSheetBinding) {
            NameInputSheet(
                icon: IconKit.newFile,
                title: L10n.Browse.newFileTitle,
                placeholder: L10n.Browse.newFilePlaceholder,
                confirmTitle: L10n.Browse.newFolderConfirm,
                isBusy: store.isPerformingFileAction,
                additionalRule: { [extensions = store.newFileServerExtensions] name in
                    EditableTextFiles.isEditable(name: name, serverExtensions: extensions)
                        ? nil
                        : L10n.Browse.newFileTypeHint
                },
                capitalizesWords: false,
                onConfirm: { store.send(.newFileConfirmed($0)) },
                onCancel: { store.send(.newFileCancelled) }
            )
        }
        .dsAlert(isPresented: isDeletingBinding) {
            deleteConfirmationSheet(dismissingPreview: false)
        }
        .dsAlert(isPresented: transferConflictBinding(inPreview: false)) {
            transferConflictSheet
        }
        .offlineRemovalAlert(
            store.previewItem == nil ? store.offlineRemoval : nil,
            onConfirm: { store.send(.offlineRemovalConfirmed, animation: DSMotion.listDiff) },
            onCancel: { store.send(.offlineRemovalCancelled) }
        )
        #if os(iOS)
        .keptFilesShareSheet(store.keptShare) { store.send(.keptShareDismissed) }
        #endif
    }

    private var previewPresentedBinding: Binding<Bool> {
        Binding(
            get: { store.previewItem != nil && store.isPreviewContentReady },
            set: {
                if !$0 {
                    store.send(.previewDismissed)
                }
            }
        )
    }

    private func isOpening(_ item: FileItem) -> Bool {
        isOpeningID(item.id)
    }

    private func isOpeningID(_ id: String) -> Bool {
        store.previewItem?.id == id && !store.isPreviewContentReady
    }

    /// Search hits and browse rows share an `id` scheme (`path/name`), so `searchResultTapped`
    /// builds a `FileItem` whose id matches the hit: the `.zoom` source and the opening
    /// spinner can key off the same value.
    private func searchResultCell(row: SearchResultItem, grid: Bool) -> some View {
        Group {
            if grid {
                GridCellView(
                    name: row.name, isDirectory: row.isDirectory,
                    isFavorite: store.favoritePaths.contains(row.id), kind: row.displayKind,
                    thumbnailFile: row.thumbnailFile,
                    serverURL: store.serverURL,
                    showThumbnails: store.preferences.showThumbnails,
                    iconSize: thumbnailSize.iconSize,
                    matchedSource: PreviewMatchedSource(
                        id: row.id,
                        namespace: previewTransition,
                        visibility: sourceVisibility
                    ),
                    isOpening: isOpeningID(row.id)
                )
            } else {
                SearchResultRow(
                    result: row,
                    knownItem: store.items[id: row.id],
                    currentFolder: store.directoryPath,
                    isFavorite: store.favoritePaths.contains(row.id),
                    serverURL: store.serverURL,
                    showThumbnails: store.preferences.showThumbnails,
                    matchedSource: PreviewMatchedSource(
                        id: row.id,
                        namespace: previewTransition,
                        visibility: sourceVisibility
                    ),
                    isOpening: isOpeningID(row.id)
                )
            }
        }
    }

    /// Extracted from the grid/list `ForEach` bodies: inlining the full cell (with the
    /// `matchedSource` / `isOpening` args) tipped those already-large expressions past the
    /// type-checker's budget.
    private func contextMenuPreview(for item: FileItem) -> some View {
        FileContextMenuPreview(item: item, serverURL: store.serverURL, showThumbnails: store.preferences.showThumbnails)
    }

    private func gridCell(for item: FileItem) -> some View {
        GridCellView(
            item: item,
            isFavorite: store.favoritePaths.contains(item.id),
            serverURL: store.serverURL,
            showThumbnails: store.preferences.showThumbnails,
            iconSize: thumbnailSize.iconSize,
            matchedSource: PreviewMatchedSource(
                id: item.id,
                namespace: previewTransition,
                visibility: sourceVisibility
            ),
            isOpening: isOpening(item),
            isAvailableOffline: store.offlineItemIDs.contains(item.id)
        )
    }

    /// Search results on the Mac table, in a table of their own.
    @ViewBuilder
    private var searchTableContent: some View {
        #if os(macOS)
            VStack(spacing: 0) {
                MacSearchScopeBar(
                    availableCategories: store.availableSearchCategories,
                    selectedCategories: store.selectedSearchCategories,
                    onToggle: { store.send(.searchCategoryToggled($0)) },
                    onShowAll: { store.send(.searchFilterCleared) }
                )
                Divider()
                MacSearchResultsTable(
                    sections: store.searchResultSections,
                    favoritePaths: store.favoritePaths,
                    onOpen: { store.send(.searchResultTapped($0)) },
                    onShowInFolder: { store.send(.searchResultEnclosingFolderTapped($0)) }
                )
                if hasSearchFooter {
                    Divider()
                    searchStatusFooter
                }
            }
            .backgroundGradient()
        #endif
    }

    private var tableContent: some View {
        #if os(macOS)
            MacBrowseTableView(
                items: store.displayedItems,
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                onSortChanged: { option, direction in
                    store.send(.sortOptionChanged(option))
                    store.send(.sortDirectionChanged(direction))
                },
                selection: Binding(
                    get: { store.selectedItemIDs },
                    set: { store.send(.tableSelectionChanged($0)) }
                ),
                cutItemIDs: store.clipboard?.operation == .move ? store.clipboard?.sourceItemPaths ?? [] : [],
                offlineItemIDs: store.offlineItemIDs,
                favoriteItemIDs: store.favoritePaths,
                onOpen: handleTap,
                keyboardActions: tableKeyboardActions,
                serverURL: store.serverURL,
                scope: store.cacheScope,
                canDropOnFolders: store.access?.canDelete ?? false,
                onDropOnFolder: { ids, folder in store.send(.itemsDroppedOnFolder(ids: ids, folder: folder)) },
                onDropForeignItemsOnFolder: { items, folder in
                    store.send(.itemsDroppedFromOtherWindow(items, destination: folder.id))
                },
                canUploadToFolders: store.canUploadHere,
                onFilesDroppedOnFolder: { urls, folder in store.send(.filesDroppedOnFolder(urls, folder: folder)) },
                contextMenu: { ids in tableContextMenu(for: ids) },
                renamingItemID: shouldRenameInTable ? store.renameSheetItem?.id : nil,
                onRenameCommit: { store.send(.renameConfirmed($0)) },
                onRenameCancel: { store.send(.renameCancelled) },
                personalSpace: showsPersonalSpace ? Self.macPersonalSpaceItem : nil,
                onOpenPersonalSpace: { store.send(.personalSpaceTapped) },
                onQuickLookUnavailable: { toastMessage = DSToastMessage(icon: IconKit.warning, text: $0) }
            )
            .focusedSceneValue(\.browseViewOptions, BrowseViewOptions(
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                setSortOption: { store.send(.sortOptionChanged($0)) },
                setSortDirection: { store.send(.sortDirectionChanged($0)) }
            ))
        #else
            listContent
        #endif
    }

    #if os(macOS)
        /// Drag a row out (Finder, or onto a folder here) and let folder rows take drops.
        private func macRowDragDrop(for item: FileItem) -> MacRowDragDrop {
            MacRowDragDrop(
                item: item,
                serverURL: store.serverURL,
                scope: store.cacheScope,
                canDrag: !store.isSelecting,
                canDropHere: !store.isSelecting && (store.access?.canDelete ?? false),
                onDrop: { ids in store.send(.itemsDroppedOnFolder(ids: ids, folder: item)) }
            )
        }
    #endif

    #if os(macOS)
        /// The table row standing in for My Files; its id is the `personal` path it opens.
        private static let macPersonalSpaceItem = FileItem(
            name: PersonalSpace.rootPath,
            path: "",
            dateModified: .distantPast,
            size: 0,
            kind: "directory"
        )

        /// Right click in the table: the clicked rows' actions, or the folder's own (new folder,
        /// upload) on empty space. Paste Here joins every variant while something is staged, so
        /// a full window still has somewhere to paste.
        @ViewBuilder
        private func tableContextMenu(for ids: Set<FileItem.ID>) -> some View {
            let items = store.displayedItems.filter { ids.contains($0.id) }
            if items.isEmpty {
                if !store.directoryPath.isEmpty, store.canCreateFolderHere {
                    Button { store.send(.newFolderTapped) } label: {
                        Label { Text(L10n.Browse.actionNewFolder) } icon: { IconKit.folder }
                    }
                    .tint(.primaryDS)
                }
                if !store.directoryPath.isEmpty, store.canCreateFileHere {
                    Button { store.send(.newFileTapped) } label: {
                        Label { Text(L10n.Browse.actionNewFile) } icon: { IconKit.newFile }
                    }
                    .tint(.primaryDS)
                }
                if store.canUploadHere {
                    Button { isFilesPickerPresented = true } label: {
                        Label { Text(L10n.Uploads.actionUploadFromFiles) } icon: { IconKit.upload }
                    }
                    .tint(.primaryDS)
                }
            } else if items.count == 1, let item = items.first {
                fileActionsMenu(for: item)
            } else {
                Section {
                    Button {
                        store.send(.tableSelectionChanged(ids))
                        store.send(.copySelectionTapped, animation: DSMotion.listDiff)
                    } label: {
                        Label { Text(L10n.Browse.actionCopy) } icon: { IconKit.copy }
                    }
                    .tint(.primaryDS)
                    if store.access?.canWrite ?? false, !store.directoryPath.isEmpty {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionDuplicate) } icon: { IconKit.duplicate }
                        }
                        .tint(.primaryDS)
                    }
                    if store.access?.canWrite ?? false, store.access?.canDelete ?? false {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.cutSelectionTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionCut) } icon: { IconKit.cut }
                        }
                        .tint(.primaryDS)
                    }
                    if store.access?.canWrite ?? false, store.access?.canDelete ?? false {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkMoveTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionMove) } icon: { IconKit.move }
                        }
                        .tint(.primaryDS)
                    }
                }
                Section {
                    // Select mode's bulk bar is iOS only, so the Mac's several row actions live here.
                    if store.access?.canDownload ?? false {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkDownloadTapped)
                        } label: {
                            Label { Text(L10n.Browse.actionDownload) } icon: { IconKit.download }
                        }
                        .tint(.primaryDS)
                    }
                }
                // Available Offline and Favorites, always their own group; a removal is red.
                Section {
                    if store.access?.canDownload ?? false {
                        let offlineAction = OfflineBulkAction.resolve(
                            selectedIDs: items.map(\.id),
                            offlineIDs: store.offlineItemIDs
                        )
                        RemovableMenuButton(
                            title: offlineAction?.title ?? L10n.Browse.actionAvailableOffline,
                            icon: offlineAction?.icon ?? IconKit.availableOffline,
                            isRemoval: offlineAction == .remove
                        ) {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkOfflineTapped)
                        }
                        .disabled(offlineAction == nil)
                    }
                    if items.allSatisfy(\.isDirectory) {
                        let isAllFavorite = items.allSatisfy { store.favoritePaths.contains($0.id) }
                        RemovableMenuButton(
                            title: isAllFavorite
                                ? L10n.Browse.actionRemoveFromFavorites
                                : L10n.Browse.actionAddToFavorites,
                            icon: isAllFavorite ? IconKit.starFill : IconKit.star,
                            isRemoval: isAllFavorite
                        ) {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkFavoriteTapped)
                        }
                        .disabled(!store.hasLoadedFavorites)
                    }
                }
                Section {
                    if store.access?.canDelete ?? false {
                        Button(role: .destructive) {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.deleteSelectionTapped)
                        } label: {
                            Label { Text(L10n.Browse.actionDelete) } icon: { IconKit.delete }
                        }
                    }
                }
            }
            if store.clipboard != nil, !store.directoryPath.isEmpty {
                Divider()
                pasteEmptySpaceMenu
                    .tint(.primaryDS)
            }
        }

        private var tableKeyboardActions: BrowseKeyboardActions {
            let canPaste = store.clipboard != nil && !store.directoryPath.isEmpty
            let keepAfterCopy = shouldKeepClipboardAfterCopy
            return BrowseKeyboardActions(
                cut: { store.send(.cutSelectionTapped) },
                copy: { store.send(.copySelectionTapped) },
                duplicate: { store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff) },
                undo: { store.send(.undoTapped, animation: DSMotion.listDiff) },
                canUndo: !store.undoStack.isEmpty,
                paste: {
                    guard canPaste else { return }
                    store.send(.pasteTapped(keepItemsAfterCopy: keepAfterCopy), animation: DSMotion.listDiff)
                },
                delete: { store.send(.deleteSelectionTapped) },
                rename: { store.send(.renameSelectionTapped) },
                selectAll: { store.send(.tableSelectionChanged(Set(store.displayedItems.map(\.id)))) },
                getInfo: { store.send(.infoSelectionTapped) },
                canPaste: canPaste,
                open: {
                    guard store.selectedItemIDs.count == 1,
                          let item = store.displayedItems.first(where: { store.selectedItemIDs.contains($0.id) })
                    else { return }
                    handleTap(item)
                },
                copyPath: {
                    let paths = store.displayedItems.filter { store.selectedItemIDs.contains($0.id) }.map(\.id)
                    guard !paths.isEmpty else { return }
                    PlatformPasteboard.copy(paths.joined(separator: "\n"))
                }
            )
        }
    #endif

    private func listRowCell(for item: FileItem) -> some View {
        FileRowView(
            item: item,
            isFavorite: store.favoritePaths.contains(item.id),
            serverURL: store.serverURL,
            showThumbnails: store.preferences.showThumbnails,
            matchedSource: PreviewMatchedSource(
                id: item.id,
                namespace: previewTransition,
                visibility: sourceVisibility
            ),
            isOpening: isOpening(item),
            isAvailableOffline: store.offlineItemIDs.contains(item.id)
        )
    }

    /// Toasts split by surface: while a preview cover is up, its toasts render over the cover,
    /// otherwise over the list. One `toastMessage`/`fileActionProgressMessage` still drives
    /// both: only the visible one is bound.
    private var listToastBinding: Binding<DSToastMessage?> {
        Binding(get: { store.previewItem == nil ? toastMessage : nil }, set: { toastMessage = $0 })
    }

    private var previewToastBinding: Binding<DSToastMessage?> {
        Binding(get: { store.previewItem != nil ? toastMessage : nil }, set: { toastMessage = $0 })
    }

    /// Read-only from the store's perspective: `fileActionProgressMessage` clears itself once
    /// the extract/compress effect resolves, so there's nothing for the view to write back:
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
    /// in-place content change: see `FileInfoLoadingSheet`'s doc comment for why that
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

    /// The info sheet over whichever surface is frontmost: the list, or the preview cover.
    private func infoPhaseBinding(inPreview: Bool) -> Binding<InfoSheetPhase?> {
        Binding(
            get: { (store.previewItem != nil) == inPreview ? infoPhase : nil },
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
    /// The Mac folder table renames in place; search results and previews keep the sheet.
    private var shouldRenameInTable: Bool {
        #if os(macOS)
            store.previewItem == nil && !store.isSearching
        #else
            false
        #endif
    }

    private var renameItemBinding: Binding<FileItem?> {
        Binding(
            get: { store.previewItem == nil && !shouldRenameInTable ? store.renameSheetItem : nil },
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

    private var newFileSheetBinding: Binding<Bool> {
        Binding(
            get: { store.isNewFileSheetPresented },
            set: {
                if !$0 {
                    store.send(.newFileCancelled)
                }
            }
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

    private func deleteConfirmationSheet(dismissingPreview: Bool) -> DSAlertSheet {
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
                if dismissingPreview, !store.isPreviewInGallery {
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
    /// Split by surface like the info sheet, so a move started in the gallery asks over the cover.
    /// Waits for the folder picker to finish closing: a card can't present while the sheet under
    /// it is still on its way out, and would be dropped.
    private func transferConflictBinding(inPreview: Bool) -> Binding<Bool> {
        Binding(
            get: {
                store.transferConflict != nil && !isDestinationPickerOnScreen
                    && (store.previewItem != nil) == inPreview
            },
            set: { _ in }
        )
    }

    private func destinationPicker(_ pickerStore: StoreOf<DestinationPickerFeature>) -> some View {
        DestinationPickerView(store: pickerStore)
            .onAppear { isDestinationPickerOnScreen = true }
    }

    private func destinationPickerDismissed() {
        isDestinationPickerOnScreen = false
    }

    private var transferConflictSheet: DSAlertSheet {
        DSAlertSheet.transferConflict(store.transferConflict) { choice in
            store.send(.transferConflictResolved(choice), animation: choice == nil ? nil : DSMotion.listDiff)
        }
    }

    /// The folder picker over whichever surface is frontmost: the list, or the preview cover.
    private func destinationPickerBinding(inPreview: Bool) -> Binding<StoreOf<DestinationPickerFeature>?> {
        let scoped = $store.scope(state: \.destinationPicker, action: \.destinationPicker)
        return Binding(
            get: { (store.previewItem != nil) == inPreview ? scoped.wrappedValue : nil },
            set: { scoped.wrappedValue = $0 }
        )
    }

    private var isAllSelected: Bool {
        store.hasDisplayedItems && store.selectedItemIDs.count == store.displayedItemCount
    }

    private var bulkDeleteConfirmationBinding: Binding<Bool> {
        Binding(get: { store.bulkDeleteConfirmationIsPresented }, set: { _ in })
    }

    private var bulkDeleteConfirmationTitle: String {
        let selected = store.items.filter { store.selectedItemIDs.contains($0.id) }
        if selected.count == 1, let item = selected.first {
            return L10n.Browse.deleteConfirmOne(item.name)
        }
        return L10n.Browse.deleteConfirmMany(store.selectedItemIDs.count)
    }

    private func fileActionsMenu(for item: FileItem) -> some View {
        FileActionsMenu(
            store: store,
            item: item,
            onShare: { shareTarget = $0 },
            onOpenWithFailed: { toastMessage = .failure($0) }
        )
    }

    /// Which branch of `overlayStateContent` is currently showing: a plain discriminant so
    /// the overlay can cross-fade between states instead of hard-cutting between them.
    private enum OverlayState: Hashable {
        case none, error, empty, searching, searchFailed, noResults
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
        } else if store.isSearchPending, store.displayedSearchResults?.isEmpty ?? true {
            // A recursive backend search is in flight with nothing to show yet (the instant
            // matches found nothing local): placeholders rather than a flash of "no results".
            .searching
        } else if store.searchFailureMessage != nil, store.displayedSearchResults?.isEmpty ?? true {
            .searchFailed
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
            // The shape of the answer to come, like a folder's first load, rather than a second
            // spinner beside the one in the search field.
            loadingSkeleton
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
                if !store.isSelecting, store.canUploadHere {
                    emptyStateUploadButton
                }
            }
            .transition(.opacity)
        case .searchFailed:
            if let message = store.searchFailureMessage {
                EmptyStateView(icon: IconKit.warning, message: message) {
                    store.send(.searchRetryTapped)
                }
                .transition(.opacity)
            }
        case .noResults:
            noResultsState
                .transition(.opacity)
        case .none:
            EmptyView()
        }
    }

    /// The toolbar's upload `+` menu; each platform supplies its own label and styling.
    private func uploadMenu(@ViewBuilder label: @escaping () -> some View) -> some View {
        UploadSourceMenu(
            label: label,
            leadingActions: {
                if !store.directoryPath.isEmpty {
                    if store.canCreateFolderHere {
                        Button { store.send(.newFolderTapped) } label: {
                            Label { Text(L10n.Browse.actionNewFolder) } icon: { IconKit.folder }
                        }
                    }
                    if store.canCreateFileHere {
                        Button { store.send(.newFileTapped) } label: {
                            Label { Text(L10n.Browse.actionNewFile) } icon: { IconKit.newFile }
                        }
                    }
                }
            },
            includesUploadSources: store.canUploadHere,
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
        )
        .accessibilityLabelWithTooltip(L10n.Uploads.menuTitle)
        .accessibilityIdentifier(AccessibilityIdentifiers.Browse.uploadMenu)
    }

    /// Root only, outside search and select mode: the account's private folder is not a volume,
    /// so it is not something a bulk action over the listing should touch.
    private var showsPersonalSpace: Bool {
        store.directoryPath.isEmpty && store.isPersonalSpaceEnabled && !store.isSearching && !store.isSelecting
    }

    private var listContent: some View {
        ScrollViewReader { proxy in
            DSGroupedList {
                if showsPersonalSpace {
                    Section {
                        PersonalSpaceRow { store.send(.personalSpaceTapped) }
                            .listRowBackground(Color.backgroundSecondary)
                    } header: {
                        BrowseRootSectionHeader(title: L10n.Browse.sectionPersonal)
                    }
                }
                if store.isSearching {
                    let sections = store.searchResultSections
                    if sections.isSplit {
                        Section {
                            searchResultRows(sections.onDevice)
                        } header: {
                            BrowseRootSectionHeader(title: L10n.Search.onDevice)
                        }
                        if !sections.remote.isEmpty {
                            Section {
                                searchResultRows(sections.remote)
                            } header: {
                                BrowseRootSectionHeader(title: L10n.Search.remote)
                            }
                        }
                    } else {
                        Section { searchResultRows(sections.remote) }
                    }
                } else {
                    Section {
                        folderItemRows
                    } header: {
                        if showsPersonalSpace {
                            BrowseRootSectionHeader(title: L10n.Browse.locations)
                        }
                    }
                }
                if store.isSearching, hasSearchFooter {
                    searchStatusFooter
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                offlineFooterRow
                pasteTargetRow
            }
            .listStyle(.insetGrouped)
            .groupedListRowHover()
            .scrollContentBackground(.hidden)
            // Scrolling the results dismisses the search keyboard, the expected gesture when the
            // results fill the screen and tapping a row would navigate rather than just defocus.
            .scrollDismissesKeyboard(.immediately)
            .modifier(BrowseDragToSelect(store: store))
            .backgroundGradient()
            .safeAreaPadding(.bottom, bottomChromeClearance)
            .scrollGalleryPageIntoView(proxy, id: galleryCurrentItemID)
        }
    }

    private var gridContent: some View {
        // Bind once: `store.displayedItems` filters + localized sorts on every read, and this
        // builder would otherwise hit it for the ForEach and the animation value separately.
        let displayedItems = store.displayedItems
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: FileGridMetrics.columns, spacing: FileGridMetrics.spacing) {
                    if store.isSearching {
                        let sections = store.searchResultSections
                        if sections.isSplit {
                            Section {
                                searchResultCells(sections.onDevice)
                            } header: {
                                BrowseRootSectionHeader(title: L10n.Search.onDevice)
                            }
                            if !sections.remote.isEmpty {
                                Section {
                                    searchResultCells(sections.remote)
                                } header: {
                                    BrowseRootSectionHeader(title: L10n.Search.remote)
                                }
                            }
                        } else {
                            searchResultCells(sections.remote)
                        }
                    } else {
                        if showsPersonalSpace {
                            Section {
                                PersonalSpaceGridCell(
                                    iconSize: thumbnailSize.iconSize,
                                    cellPadding: FileGridMetrics.cellPadding
                                ) {
                                    store.send(.personalSpaceTapped)
                                }
                            } header: {
                                BrowseRootSectionHeader(title: L10n.Browse.sectionPersonal)
                            }
                        }
                        Section {
                            gridItemCells(displayedItems)
                        } header: {
                            if showsPersonalSpace {
                                BrowseRootSectionHeader(title: L10n.Browse.locations)
                            }
                        }
                    }
                }
                .padding(FileGridMetrics.spacing)
                .animation(
                    DSMotion.listDiff,
                    value: displayedItems
                )
                .animation(
                    DSMotion.listDiff,
                    value: store.displayedSearchResults
                )
                if store.isSearching, hasSearchFooter {
                    searchStatusFooter
                }
                offlineFooter
                pasteTargetArea
            }
            .scrollDismissesKeyboard(.immediately)
            .modifier(BrowseDragToSelect(store: store))
            .backgroundGradient()
            .safeAreaPadding(.bottom, bottomChromeClearance)
            .dismissKeyboardOnTap()
            .scrollGalleryPageIntoView(proxy, id: galleryCurrentItemID)
        }
    }

    /// Invisible long-press target filling the space past the last row: a plain
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

    private var searchStatusMessage: String? {
        SearchStatusFooter.message(
            failure: store.searchFailureMessage,
            isTooShort: store.isSearchTermTooShort,
            shortfall: store.searchShortfall
        )
    }

    /// A search in a folder can be widened to everywhere, unless the term is too short for the
    /// server to search at all.
    private var canOfferWiderSearch: Bool {
        store.canWidenSearch && !store.isSearchTermTooShort
    }

    private var hasSearchFooter: Bool {
        searchStatusMessage != nil || canOfferWiderSearch
    }

    private var searchStatusFooter: some View {
        SearchStatusFooter(
            message: searchStatusMessage,
            canShowMore: store.canShowMoreSearchResults && store.searchPhase != .loading,
            onShowMore: { store.send(.searchShowMoreTapped) },
            onSearchEverywhere: canOfferWiderSearch ? { store.send(.searchScopeChanged(.everywhere)) } : nil,
            onRetry: store.searchFailureMessage == nil ? nil : { store.send(.searchRetryTapped) }
        )
    }

    /// "Showing a saved copy" notice, rendered as a footer below the last row/cell of the
    /// list/grid (not a blocking overlay) whenever the listing on screen came from the offline
    /// cache. Scrolls with the content, so a reachable listing shows nothing extra.
    @ViewBuilder
    private var offlineFooter: some View {
        if case let .cached(fetchedAt) = store.dataSource {
            let text = L10n.Browse.offlineBannerDetail(OfflineRelativeTime.string(from: fetchedAt))
            #if os(macOS)
                // Under the Mac table: a quiet line in the corner, not a card.
                Label { Text(text) } icon: { IconKit.info }
                    .type(.caption(.regular), style: .secondary)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .space16)
                    .padding(.vertical, .space8)
            #else
                DSInfoCard(text)
                    .padding(.horizontal, .space16)
                    .padding(.top, .space12)
            #endif
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

    /// Bottom scroll clearance for the chrome floating under this list: the split view's path
    /// bar (`SplitDetailBreadcrumb`, below a tab's root only) and the app wide upload progress
    /// bar while it's showing. Both are placed by ancestors a `List` inside a pushed
    /// `navigationDestination` doesn't reliably respect. The path bar stands above the home
    /// indicator while the list scrolls down to the screen's edge, so that inset counts too.
    private var bottomChromeClearance: CGFloat {
        let showsPathBar = !store.directoryPath.isEmpty && BrowseBreadcrumbBarMetrics
            .isShown(browseViewModeRaw: viewModeRaw, isSplitViewDetail: isSplitViewDetail)
        return (showsPathBar ? BrowseBreadcrumbBarMetrics.contentClearance + bottomSafeInset : 0)
            + (isUploadBarVisible ? uploadBarHeight + UploadBarChrome.gap : 0)
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
        .frame(maxWidth: Constants.emptyUploadButtonMaxWidth)
        .padding(.horizontal, Constants.emptyUploadButtonHPadding)
        .accessibilityLabelWithTooltip(L10n.Uploads.menuTitle)
    }

    /// Whether the current folder is a legitimate paste target for the staged clipboard:
    /// gates the "Paste" action in the `…` menu.
    private var canPasteIntoCurrentFolder: Bool {
        store.clipboard?.canPaste(into: store.directoryPath, canWrite: store.access?.canWrite ?? false) ?? false
    }

    /// "Paste" for a single staged item, "Paste N items" past that.
    private var pasteActionTitle: String {
        let count = store.clipboard?.items.count ?? 0
        return count <= 1 ? L10n.Browse.actionPaste : L10n.Browse.actionPasteCount(count)
    }

    /// Long-press menu for the empty space in the list/grid: only present while something is
    /// staged, so an empty menu never opens. Mirrors the `…` menu's paste/clear pair.
    @ViewBuilder
    private var pasteEmptySpaceMenu: some View {
        if store.clipboard != nil, !store.directoryPath.isEmpty {
            Button {
                store.send(.pasteTapped(keepItemsAfterCopy: shouldKeepClipboardAfterCopy), animation: DSMotion.listDiff)
            } label: {
                Label { Text(L10n.Browse.actionPasteHere) } icon: { IconKit.paste }
            }
            .disabled(!canPasteIntoCurrentFolder)
            Button {
                store.send(.clipboardCleared, animation: DSMotion.listDiff)
            } label: {
                Label { Text(L10n.Browse.actionClearClipboard) } icon: { IconKit.close }
            }
        }
    }

    private func gridItemCells(_ items: IdentifiedArrayOf<FileItem>) -> some View {
        ForEach(items) { item in
            Button {
                if store.isSelecting {
                    store.send(.itemSelectionToggled(item.id))
                } else {
                    handleTap(item)
                }
            } label: {
                gridCell(for: item)
                    .dsGridTile(
                        padding: FileGridMetrics.cellPadding,
                        isSelecting: store.isSelecting,
                        isSelected: store.selectedItemIDs.contains(item.id),
                        seed: item.id
                    )
                    .dragSelectable(id: item.id)
                #if os(macOS)
                    .modifier(macRowDragDrop(for: item))
                #else
                    .modifier(IOSBrowseItemDragDrop(store: store, item: item))
                #endif
            }
            .buttonStyle(DSPressableButtonStyle())
            .dsTapFlash()
            .contextMenu {
                if !store.isSelecting {
                    fileActionsMenu(for: item)
                }
            } preview: {
                contextMenuPreview(for: item)
            }
            // A tile has no swipe, so VoiceOver gets the row's swipe actions as its own.
            .accessibilityActions {
                BrowseQuickActionButtons(
                    actions: BrowseQuickAction.actions(for: item, store: store),
                    style: .accessibility
                )
            }
        }
    }

    @ViewBuilder
    private var folderItemRows: some View {
        // `store.displayedItems` filters + sorts on every read: bind it once here rather than
        // re-deriving it per row (the separator checks below alone made it O(n^2 log n)).
        let items = store.displayedItems
        let firstItemID = items.first?.id
        let lastItemID = items.last?.id
        ForEach(items) { item in
            DSFlashingListRow {
                Button {
                    if store.isSelecting {
                        store.send(.itemSelectionToggled(item.id))
                    } else {
                        handleTap(item)
                    }
                } label: {
                    listRowCell(for: item)
                        .dsListSelection(
                            isSelecting: store.isSelecting,
                            isSelected: store.selectedItemIDs.contains(item.id)
                        )
                        .dragSelectable(id: item.id)
                    #if os(macOS)
                        // On the label, not the row chain: that chain is at the type checker's limit.
                        .modifier(macRowDragDrop(for: item))
                    #else
                        .modifier(IOSBrowseItemDragDrop(store: store, item: item))
                    #endif
                }
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityAddTraits(store.isSelecting && store.selectedItemIDs
                    .contains(item.id) ? [.isSelected] : [])
                .contextMenu {
                    if !store.isSelecting {
                        fileActionsMenu(for: item)
                    }
                } preview: {
                    contextMenuPreview(for: item)
                }
                .swipeActions(edge: .trailing) {
                    BrowseQuickActionButtons(actions: BrowseQuickAction.actions(for: item, store: store), style: .swipe)
                }
                .listRowSeparator(item.id == firstItemID ? .hidden : .visible, edges: .top)
                .listRowSeparator(item.id == lastItemID ? .hidden : .visible, edges: .bottom)
            }
        }
    }

    private func searchResultCells(_ results: [SearchResultItem]) -> some View {
        ForEach(results) { result in
            Button {
                store.send(.searchResultTapped(result))
            } label: {
                searchResultCell(row: result, grid: true)
                    .dsGridTile(padding: FileGridMetrics.cellPadding)
            }
            .buttonStyle(DSPressableButtonStyle())
            .contextMenu { searchResultMenu(result) }
            .dsTapFlash()
        }
    }

    private func searchResultMenu(_ result: SearchResultItem) -> some View {
        SearchResultMenu(
            result: result,
            onOpen: { store.send(.searchResultTapped(result)) },
            onShowInFolder: { store.send(.searchResultEnclosingFolderTapped(result)) }
        )
    }

    private func searchResultRows(_ results: [SearchResultItem]) -> some View {
        ForEach(results) { result in
            DSFlashingListRow {
                Button {
                    store.send(.searchResultTapped(result))
                } label: {
                    searchResultCell(row: result, grid: false)
                }
                .buttonStyle(DSPressableButtonStyle())
                .contextMenu { searchResultMenu(result) }
                .listRowSeparator(result.id == results.first?.id ? .hidden : .visible, edges: .top)
                .listRowSeparator(result.id == results.last?.id ? .hidden : .visible, edges: .bottom)
            }
        }
    }

    private var noResultsState: some View {
        #if os(macOS)
            ContentUnavailableView {
                Label { Text(L10n.Browse.searchNoMatchesInFolder(store.searchQuery)) } icon: { IconKit.search }
            } description: {
                if store.isSearchTermTooShort {
                    Text(SearchStatusFooter.tooShortMessage)
                }
            } actions: {
                if store.canWidenSearch, !store.isSearchTermTooShort {
                    Button(L10n.Browse.searchEverywhere) { store.send(.searchScopeChanged(.everywhere)) }
                }
            }
        #else
            iOSNoResultsState
        #endif
    }

    private var iOSNoResultsState: some View {
        VStack(spacing: Constants.emptyStateSpacing) {
            IconKit.search
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.emptyStateIconSize, height: Constants.emptyStateIconSize)
            Text(L10n.Browse.searchNoMatchesInFolder(store.searchQuery))
                .type(.body1(.semibold), style: .secondary)
            if store.isSearchTermTooShort {
                Text(SearchStatusFooter.tooShortMessage)
                    .type(.body3(.regular), style: .secondary)
                    .multilineTextAlignment(.center)
            } else if store.canWidenSearch {
                DSButton(
                    L10n.Browse.searchEverywhere,
                    icon: IconKit.search,
                    style: .secondary,
                    size: .small,
                    isLoading: false,
                    action: {
                        store.send(.searchScopeChanged(.everywhere))
                    }
                )
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
    FileItem(
        name: "cover.jpg",
        path: "Documents",
        dateModified: Date(),
        size: 2_400_000,
        kind: "jpg",
        supportsThumbnail: true
    ),
]

private let browsePreviewEmptyAccess = FileAccess(
    canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
)

#Preview("Browse: content") {
    browsePreview(mutateState: { $0.items = IdentifiedArray(uniqueElements: browsePreviewItems) })
}

#Preview("Browse: loading") {
    browsePreview(mutateState: { $0.phase = .loading })
}

#Preview("Browse: empty folder") {
    browsePreview(
        configureClient: { $0.browse = { _, path in
            BrowseResult(items: [], access: browsePreviewEmptyAccess, path: path)
        } }
    )
}

#Preview("Browse: error") {
    browsePreview(mutateState: { $0.phase = .failed(L10n.EmptyState.loadFailed) })
}

#Preview("Browse: no search results") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchResults = []
    })
}

#Preview("Browse: searching everywhere") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchScope = .everywhere
        $0.searchPhase = .loading
    })
}

#Preview("Browse: search failed") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchResults = []
        $0.searchPhase = .failed(L10n.Browse.searchFailed)
    })
}

#Preview("Browse: delete alert, linked shares") {
    browsePreview(mutateState: {
        $0.items = IdentifiedArray(uniqueElements: browsePreviewItems)
        $0.deleteConfirmationItem = browsePreviewItems[1]
        $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 2))
    })
}

#Preview("Browse: delete alert, share check unavailable") {
    browsePreview(mutateState: {
        $0.items = IdentifiedArray(uniqueElements: browsePreviewItems)
        $0.deleteConfirmationItem = browsePreviewItems[1]
        $0.deleteImpactCheck = .unavailable
    })
}
