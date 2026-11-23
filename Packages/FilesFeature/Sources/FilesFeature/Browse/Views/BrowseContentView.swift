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
    /// The item whose "Create Share Link" sheet is open; the sheet owns its own store.
    @State private var shareTarget: FileItem?
    /// Flipped when a pull to refresh completes, only as a `.hapticFeedback` trigger.
    @State private var hasFinishedRefreshing = false
    @State private var isFilesPickerPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isCameraDeniedAlertPresented = false
    @State private var photosSelection: [PhotosPickerItem] = []
    /// Pairs each cell with the preview cover for the native `.zoom` open and swipe to dismiss.
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
            return .table
        #else
            let mode = BrowseViewMode(rawValue: viewModeRaw) ?? .list
            return mode == .table ? .list : mode
        #endif
    }

    /// The root's title is rederived from `L10n` here rather than read from `store.title` (which
    /// captured it once at login) so it relocalizes live when the language changes. Pushed
    /// subfolders show their real folder name from `store.title`.
    private var displayTitle: String {
        store.directoryPath.isEmpty ? L10n.Browse.navigationTitle : store.title
    }

    private var previewSource: BrowsePreviewSource {
        BrowsePreviewSource(namespace: previewTransition, visibility: sourceVisibility)
    }

    private func handleTap(_ item: FileItem) {
        // A second tap while the row spinner is up cancels the in flight open (a slow fetch
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
                // `isPresented`, not `item:`; so an in place rename (which changes the item's
                // id) updates the cover's content instead of dismissing and re presenting it.
                if let item = store.previewItem {
                    BrowsePreviewCover(
                        store: store,
                        item: item,
                        zoomContext: PreviewZoomContext(namespace: previewTransition, visibility: sourceVisibility),
                        galleryCurrentItemID: $galleryCurrentItemID,
                        shareTarget: $shareTarget,
                        isDestinationPickerOnScreen: $isDestinationPickerOnScreen,
                        toastMessage: $toastMessage
                    )
                }
            }
            .modifier(BrowseActionSheets(
                store: store,
                isInPreview: false,
                shareTarget: $shareTarget,
                isDestinationPickerOnScreen: $isDestinationPickerOnScreen
            ))
            .modifier(BrowseToasts(
                store: store,
                toastMessage: $toastMessage,
                isInPreview: false,
                extraBottomInset: bottomChromeClearance
            ))
            .modifier(BrowseToastEvents(store: store, toastMessage: $toastMessage))
            .modifier(BrowseScreenLifecycle(
                store: store,
                sourceVisibility: sourceVisibility,
                shareTarget: $shareTarget,
                galleryCurrentItemID: $galleryCurrentItemID
            ))
        #if os(macOS)
            .modifier(MacBrowseInspector(
                screen: store,
                onOpen: handleTap,
                onShare: { shareTarget = $0 },
                more: { MacInspectorMoreMenu(store: store, item: $0) { toastMessage = .failure($0) } }
            ))
        #endif
    }

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
            } else if viewMode == .table, store.isSearching || !store.isSelecting {
                #if os(macOS)
                    MacBrowseContentTable(
                        store: store,
                        shouldKeepClipboard: shouldKeepClipboardAfterCopy,
                        isFilesPickerPresented: $isFilesPickerPresented,
                        onOpen: handleTap,
                        onQuickLookUnavailable: { toastMessage = DSToastMessage(icon: IconKit.errorFill, text: $0) }
                    ) { fileActionsMenu(for: $0) }
                #endif
            } else if viewMode != .grid {
                BrowseListContent(
                    store: store,
                    source: previewSource,
                    shouldKeepClipboard: shouldKeepClipboardAfterCopy,
                    bottomClearance: bottomChromeClearance,
                    scrollTargetID: galleryCurrentItemID,
                    onTap: handleTap
                ) { fileActionsMenu(for: $0) }
                    .transition(.opacity)
            } else {
                BrowseGridContent(
                    store: store,
                    source: previewSource,
                    shouldKeepClipboard: shouldKeepClipboardAfterCopy,
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
            hasFinishedRefreshing.toggle()
        }
        #if os(macOS)
        .macToolbarRefresh(onRefresh: { await store.send(.refreshButtonTapped).finish() }) {
            hasFinishedRefreshing.toggle()
        }
        .focusedSceneValue(
            \.uploadToVisibleFolder,
            !store.isSelecting && store.canUploadHere
                ? UploadToVisibleFolderAction { isFilesPickerPresented = true }
                : nil
        )
        .syncCompletedToast(
            hasFinishedRefreshing: hasFinishedRefreshing,
            isErrorFree: store.phase.errorMessage == nil,
            extraBottomInset: bottomChromeClearance
        )
        #endif
        .focusedSceneValue(\.browseCreateAvailability, store.createAvailability)
        .hapticFeedback(.success, trigger: hasFinishedRefreshing) { _, _ in store.phase.errorMessage == nil }
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
                subtitle: store.headerSubtitle,
                crumbs: store.headerCrumbs,
                onCrumbTapped: { store.send(.delegate(.openPath(path: $0.path, title: $0.title))) },
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
                onTrash: store.shouldShowTrashButton && !isSplitViewDetail ? { store.send(.trashTapped) } : nil,
                hasClipboardItems: store.clipboard != nil && !store.directoryPath.isEmpty,
                clipboardMenu: {
                    BrowseClipboardMenu(store: store, shouldKeepClipboard: shouldKeepClipboardAfterCopy)
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
                        BrowseUploadMenu(
                            store: store,
                            isFilesPickerPresented: $isFilesPickerPresented,
                            isPhotosPickerPresented: $isPhotosPickerPresented,
                            isCameraPresented: $isCameraPresented,
                            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
                        )
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
            BrowseSelectionToolbar(store: store) { shareTarget = $0 }
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
        BrowseOverlayContent(store: store, skeleton: { loadingSkeleton }, emptyFolder: { emptyFolderActions })
    }

    private var isInitialLoad: Bool {
        !store.isListingKnown && store.items.isEmpty && store.phase.errorMessage == nil
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

    private var emptyFolderActions: some View {
        BrowseEmptyFolderActions(
            store: store,
            title: displayTitle,
            shouldKeepClipboard: shouldKeepClipboardAfterCopy,
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
        )
    }
}
