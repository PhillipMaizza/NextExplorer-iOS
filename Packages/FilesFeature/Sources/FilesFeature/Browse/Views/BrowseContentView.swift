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
    static let emptyUploadButtonHPadding: CGFloat = .space24
    /// Keeps the empty folder's dashed upload button from spanning an iPad's full width.
    static let emptyUploadButtonMaxWidth: CGFloat = 360
}

/// The list body shown at every depth of Browse: root and every pushed subfolder render this
/// same view, scoped to their own `BrowseFeature` store. The list/grid choice is a per device
/// display preference, so it's stored here rather than in `BrowseFeature.State`.
struct BrowseContentView: View {
    @Bindable var store: StoreOf<BrowseFeature>
    /// Observed only to refresh the offline badges when a download completes.
    @AppStorage(AppStorageKeys.browseViewMode) private var viewModeRaw = BrowseViewMode.list.rawValue
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

    /// The root's title is re-derived from `L10n` here rather than read from `store.title` (which
    /// captured it once at login) so it re-localizes live when the language changes. Pushed
    /// subfolders show their real folder name from `store.title`.
    private var displayTitle: String {
        store.directoryPath.isEmpty ? L10n.Browse.navigationTitle : store.title
    }

    private var previewSource: BrowsePreviewSource {
        BrowsePreviewSource(namespace: previewTransition, visibility: sourceVisibility)
    }

    private func handleTap(_ item: FileItem) {
        // A second tap while the row spinner is up cancels the in-flight open (a slow fetch
        // has no other way out: the cover isn't presented yet).
        if previewSource.isOpening(item.id, in: store) {
            store.send(.previewDismissed)
            return
        }
        store.send(.rowTapped(item))
    }

    var body: some View {
        browsingContent
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafeInset = $0 }
            .dsSheet(item: $store.scope(state: \.uploadReview, action: \.uploadReview)) { reviewStore in
                UploadReviewView(store: reviewStore)
            }
            .dsSheet(item: $store.scope(state: \.permissions, action: \.permissions)) { permissionsStore in
                PermissionsSheet(store: permissionsStore)
            }
            .fullScreenCover(isPresented: previewPresentedBinding) {
                // `isPresented`, not `item:`; so an in-place rename (which changes the item's
                // id) updates the cover's content instead of dismissing and re-presenting it.
                if let item = store.previewItem {
                    ZoomingPreview(
                        sourceID: galleryCurrentItemID ?? item.id,
                        context: PreviewZoomContext(namespace: previewTransition, visibility: sourceVisibility)
                    ) {
                        BrowsePreviewRouter(
                            store: store,
                            item: item,
                            onShareTarget: { shareTarget = $0 },
                            onGalleryItemChange: { galleryCurrentItemID = $0.id }
                        )
                    }
                    .modifier(BrowseActionSheets(
                        store: store,
                        inPreview: true,
                        shareTarget: $shareTarget,
                        isDestinationPickerOnScreen: $isDestinationPickerOnScreen
                    ))
                    // The preview stays put through downloads and renames: their result
                    // toasts surface over the cover, and "Open" on a download routes back
                    // through the reducer so the cover dismisses before the tab switches.
                    .modifier(BrowseToasts(
                        store: store,
                        toastMessage: $toastMessage,
                        inPreview: true,
                        extraBottomInset: Constants.previewToolbarToastInset
                    ))
                }
            }
            .modifier(BrowseActionSheets(
                store: store,
                inPreview: false,
                shareTarget: $shareTarget,
                isDestinationPickerOnScreen: $isDestinationPickerOnScreen
            ))
            .modifier(BrowseToasts(
                store: store,
                toastMessage: $toastMessage,
                inPreview: false,
                extraBottomInset: bottomChromeClearance
            ))
            .modifier(BrowseToastEvents(store: store, toastMessage: $toastMessage))
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
            // Keyed on the folder: a jump to another folder at the same depth swaps this screen's store
            // under the same view, which must start loading it too.
            .task(id: store.directoryPath) {
                // Yield first so these sends land after whatever action presented this view has
                // finished reducing, never reentrantly during it (TCA forbids reentrant sends).
                await Task.yield()
                // Gone already (a jump replaced this screen): its element is no longer in the stack.
                guard !Task.isCancelled else { return }
                store.send(.onAppear)
                store.send(.computeOfflineAvailability)
            }
            // A search hit opened this folder: once its listing holds the file, select it.
            .task(id: RevealKey(
                id: store.revealItemID,
                isListed: store.revealItemID.map { store.items[id: $0] != nil }
            )) {
                guard let id = store.revealItemID, store.items[id: id] != nil else { return }
                store.send(.revealItemShown(id))
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
            BrowseSkeletonView(isGridView: viewMode == .grid)
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
                    BrowseOfflineFooter(dataSource: store.dataSource)
                }
                .transition(.opacity)
            } else if viewMode == .table, store.isSearching {
                searchTableContent
                    .transition(.opacity)
            } else if viewMode != .grid {
                BrowseListContent(
                    store: store,
                    source: previewSource,
                    keepsClipboard: shouldKeepClipboardAfterCopy,
                    bottomClearance: bottomChromeClearance,
                    scrollTargetID: galleryCurrentItemID,
                    onTap: handleTap
                ) { fileActionsMenu(for: $0) }
                    .transition(.opacity)
            } else {
                BrowseGridContent(
                    store: store,
                    source: previewSource,
                    keepsClipboard: shouldKeepClipboardAfterCopy,
                    bottomClearance: bottomChromeClearance,
                    scrollTargetID: galleryCurrentItemID,
                    onTap: handleTap
                ) { fileActionsMenu(for: $0) }
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
        .focusedSceneValue(
            \.uploadToVisibleFolder,
            !store.isSelecting && store.canUploadHere
                ? UploadToVisibleFolderAction { isFilesPickerPresented = true }
                : nil
        )
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
                selectionTitle: store.isSelecting ? L10n.Common.selectedCount(store.selectedItems.count) : nil,
                searchText: $store.searchQuery.sending(\.searchQueryChanged),
                shouldFadeIntoContent: viewMode != .table,
                isSearchPending: store.isSearchPending
            ) {
                // The Mac shows these natively, as a scope bar and search field tokens.
                #if os(iOS)
                    BrowseFilterChipRow(store: store)
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
                onTrash: store.showsTrashButton && !isSplitViewDetail ? { store.send(.trashTapped) } : nil,
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
                                Label { Text(BrowsePasteMenu.actionTitle(store)) } icon: { IconKit.paste }
                            }
                            .disabled(!BrowsePasteMenu.canPaste(store))
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
        .modifier(BrowseListSheets(store: store, isSortSheetPresented: $isSortSheetPresented))
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
                if BrowseSearchFooter.isShown(store) {
                    Divider()
                    BrowseSearchFooter(store: store)
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
                folderSizes: store.folderSizes,
                onOpen: handleTap,
                keyboardActions: BrowseKeyboardActions(
                    store: store,
                    keepsClipboard: shouldKeepClipboardAfterCopy,
                    open: handleTap
                ),
                serverURL: store.serverURL,
                scope: store.cacheScope,
                canDropOnFolders: store.access?.canDelete ?? false,
                onDropOnFolder: { ids, folder in store.send(.itemsDroppedOnFolder(ids: ids, folder: folder)) },
                onDropForeignItemsOnFolder: { items, folder in
                    store.send(.itemsDroppedFromOtherWindow(items, destination: folder.id))
                },
                canUploadToFolders: store.canUploadHere,
                onFilesDroppedOnFolder: { urls, folder in store.send(.filesDroppedOnFolder(urls, folder: folder)) },
                contextMenu: { ids in
                    MacBrowseTableContextMenu(
                        store: store,
                        ids: ids,
                        keepsClipboard: shouldKeepClipboardAfterCopy,
                        isFilesPickerPresented: $isFilesPickerPresented
                    ) { fileActionsMenu(for: $0) }
                },
                renamingItemID: store.renamesInTable ? store.renameSheetItem?.id : nil,
                onRenameCommit: { store.send(.renameConfirmed($0)) },
                onRenameCancel: { store.send(.renameCancelled) },
                personalSpace: store.showsPersonalSpace ? Self.macPersonalSpaceItem : nil,
                onOpenPersonalSpace: { store.send(.personalSpaceTapped) },
                onQuickLookUnavailable: { toastMessage = DSToastMessage(icon: IconKit.warning, text: $0) },
                scrollTargetID: store.scrollTargetID
            )
            .focusedSceneValue(\.browseViewOptions, BrowseViewOptions(
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                setSortOption: { store.send(.sortOptionChanged($0)) },
                setSortDirection: { store.send(.sortDirectionChanged($0)) }
            ))
        #else
            BrowseListContent(
                store: store,
                source: previewSource,
                keepsClipboard: shouldKeepClipboardAfterCopy,
                bottomClearance: bottomChromeClearance,
                scrollTargetID: galleryCurrentItemID,
                onTap: handleTap
            ) { fileActionsMenu(for: $0) }
        #endif
    }

    #if os(macOS)
        /// The table row standing in for My Files; its id is the `personal` path it opens.
        private static let macPersonalSpaceItem = FileItem(
            name: PersonalSpace.rootPath,
            path: "",
            dateModified: .distantPast,
            size: 0,
            kind: "directory"
        )

    #endif

    private var isAllSelected: Bool {
        store.hasDisplayedItems && store.selectedItems.count == store.displayedItemCount
    }

    private func fileActionsMenu(for item: FileItem) -> some View {
        FileActionsMenu(
            store: store,
            item: item,
            onShare: { shareTarget = $0 },
            onOpenWithFailed: { toastMessage = .failure($0) }
        )
    }

    /// A fetch with nothing yet to show: the first load of this folder (including the frame
    /// before `onAppear` starts it) or a retry after a failed first load. Drives the loading
    /// skeleton and suppresses the empty state so a fresh folder never flashes "folder is
    /// empty" for a frame.
    private var overlayState: BrowseOverlayState {
        BrowseOverlayState(store: store)
    }

    private var overlayStateContent: some View {
        BrowseOverlayContent(store: store, skeleton: { loadingSkeleton }, uploadButton: { emptyStateUploadButton })
    }

    private var isInitialLoad: Bool {
        !store.phase.hasLoaded && store.items.isEmpty && store.phase.errorMessage == nil
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
}

private struct RevealKey: Hashable {
    let id: String?
    let isListed: Bool?
}
