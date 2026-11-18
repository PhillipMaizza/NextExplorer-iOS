import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    /// Uneven redacted name / size / location widths so the skeleton doesn't line up as flat
    /// columns. Each row is `(name, "size • location")`.
    static let skeletonEntries = [
        (8, 4, 7), (13, 5, 4), (6, 3, 9), (11, 4, 5), (16, 5, 6),
        (7, 3, 8), (10, 4, 4), (5, 4, 10), (12, 5, 5), (9, 3, 7),
    ].map { name, size, location in
        SkeletonEntry(
            name: SkeletonEntry.text(name),
            subtitle: "\(SkeletonEntry.text(size)) • \(SkeletonEntry.text(location))"
        )
    }
}

struct OfflineTabView: View {
    @Bindable var store: StoreOf<OfflineTabFeature>
    let offlineStore: StoreOf<OfflineManageFeature>
    /// Favorites, so a pinned favorite folder keeps its icon and color.
    var favorites: IdentifiedArrayOf<Favorite> = []
    /// The offline run's phase, kept here so the list updates per phase, not per progress tick.
    @State private var offlinePhase = OfflineDownloadProgress.Phase.idle
    /// The same list or grid choice as Browse and Favorites, so a folder opened from this tab keeps it.
    @AppStorage(AppStorageKeys.browseViewMode) private var viewModeRaw = FileListViewMode.list.rawValue

    @State private var previewedDownload: LocalDownload?
    /// Native `.zoom` open + swipe to dismiss morph between a kept file or download and its preview.
    @Namespace private var previewTransition
    @State private var sourceVisibility = PreviewSourceVisibility()

    private var zoom: PreviewZoomContext {
        PreviewZoomContext(namespace: previewTransition, visibility: sourceVisibility)
    }

    @State private var isSortSheetPresented = false

    private var viewMode: FileListViewMode {
        #if os(macOS)
            .list
        #else
            FileListViewMode(rawValue: viewModeRaw) ?? .list
        #endif
    }

    /// The Mac lists the tab as a table once it loads, like Favorites; the skeleton list stands in before.
    private var isMacTable: Bool {
        #if os(macOS)
            listPhase != .loading
        #else
            false
        #endif
    }

    /// The pinned items to show: filtered by the search text and ordered like the downloads.
    private var displayedPinned: [OfflinePinnedRootUsage] {
        OfflineTabFeature.displayedPinned(
            offlineStore.usages,
            searchQuery: store.searchQuery,
            sortOption: store.sortOption,
            sortDirection: store.sortDirection
        )
    }

    private var isAllSelected: Bool {
        store.selectedCount > 0 && store.selectedDownloadIDs.count == store.displayedDownloads.count
            && store.selectedPinnedPaths.count == displayedPinned.count
    }

    /// In select mode a pinned item is picked; otherwise a folder opens in place and a file in a preview.
    private func pinnedTapped(_ root: OfflinePinnedRoot) {
        store.send(store.isSelecting ? .pinnedSelectionToggled(path: root.path) : .pinnedItemTapped(root))
    }

    private var selectedDownloadURLs: [URL] {
        store.downloads.filter { store.selectedDownloadIDs.contains($0.id) }.map(\.url)
    }

    /// The one screen state, derived from the store: skeleton until the first response lands
    /// (`store.phase`), then error, empty, no results, or the list. `phase.errorMessage` is
    /// non nil only on a first load failure with nothing to show, so it needs no empty guard.
    private var listPhase: ListPhase {
        .derive(
            hasError: store.errorMessage != nil,
            hasLoaded: store.phase.hasLoaded,
            isEmpty: store.downloads.isEmpty && offlineStore.isEmpty,
            hasNoResults: !store.searchQuery.isEmpty && store.displayedDownloads.isEmpty && displayedPinned.isEmpty
        )
    }

    private var renameItemBinding: Binding<LocalDownload?> {
        Binding(get: { store.renameItem }, set: {
            if $0 == nil {
                store.send(.renameCancelled)
            }
        })
    }

    @ViewBuilder
    private var downloadRows: some View {
        // Bound once: `displayedDownloads` filters + sorts on every read, and the separator
        // checks below would otherwise derive again it per row.
        let downloads = store.displayedDownloads
        let firstID = downloads.first?.id
        let lastID = downloads.last?.id
        ForEach(downloads) { download in
            DownloadListRow(
                store: store,
                download: download,
                zoom: zoom,
                isFirst: download.id == firstID,
                isLast: download.id == lastID,
                onPreview: { previewedDownload = download }
            )
        }
    }

    private var listContent: some View {
        DSGroupedList {
            if listPhase == .loading {
                SkeletonFileRows(entries: Constants.skeletonEntries)
            } else {
                if isShowingPinned {
                    OfflinePinnedSection(
                        store: offlineStore,
                        usages: displayedPinned,
                        phase: offlinePhase,
                        favorites: favorites,
                        serverURL: store.serverURL,
                        showThumbnails: store.preferences.showThumbnails,
                        isSelecting: store.isSelecting,
                        selectedPaths: store.selectedPinnedPaths,
                        zoom: zoom,
                        onOpen: pinnedTapped
                    )
                }
                if isShowingPinned, !store.downloads.isEmpty {
                    Section { downloadRows } header: { DSFieldLabel(L10n.Offline.sectionSavedEarlier) }
                } else {
                    downloadRows
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .modifier(OfflineTabDragToSelect(store: store, pinnedPaths: displayedPinned.map(\.root.path)))
        .backgroundGradient()
        .dismissKeyboardOnTap()
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FileGridMetrics.sectionSpacing) {
                if listPhase == .loading {
                    FileGrid {
                        SkeletonGridCells(entries: Constants.skeletonEntries)
                    }
                } else {
                    OfflinePinnedGrid(
                        cells: OfflinePinnedGridCells(
                            store: offlineStore,
                            usages: displayedPinned,
                            favorites: favorites,
                            serverURL: store.serverURL,
                            showThumbnails: store.preferences.showThumbnails,
                            isSelecting: store.isSelecting,
                            selectedPaths: store.selectedPinnedPaths,
                            zoom: zoom,
                            onOpen: pinnedTapped
                        )
                    ) {
                        downloadCells
                    }
                }
            }
            .padding(FileGridMetrics.margin)
            .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedDownloads)
        }
        .modifier(OfflineTabDragToSelect(store: store, pinnedPaths: displayedPinned.map(\.root.path)))
        .backgroundGradient()
        .dismissKeyboardOnTap()
    }

    private var isShowingPinned: Bool {
        !displayedPinned.isEmpty
    }

    private var downloadCells: some View {
        ForEach(store.displayedDownloads) { download in
            DownloadGridCell(
                store: store,
                download: download,
                zoom: zoom,
                onPreview: { previewedDownload = download }
            )
        }
    }

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            Group {
                if isMacTable {
                    #if os(macOS)
                        MacOfflineTableView(
                            store: store,
                            offlineStore: offlineStore,
                            pinned: displayedPinned,
                            saved: store.displayedDownloads,
                            favorites: favorites,
                            onPreview: { previewedDownload = $0 }
                        )
                        .backgroundGradient()
                        .transition(.opacity)
                    #endif
                } else if viewMode == .list {
                    listContent
                } else {
                    gridContent
                }
            }
            // Full bleed *before* `.overlay` below: without a frame fixed to the screen size
            // up front, the List's own intrinsic size can lag a frame behind on first
            // appearance, and the overlay (centered by default on whatever frame it currently
            // sees) visibly slides from that transient small frame to the real one.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                PinnedTitleSearchHeader(
                    title: L10n.Tab.offline,
                    selectionTitle: store.isSelecting ? L10n.Common.selectedCount(store.selectedCount) : nil,
                    searchText: $store.searchQuery.sending(\.searchQueryChanged),
                    shouldFadeIntoContent: !isMacTable
                )
            }
            // No refresh control: the tab lists what is on the device, read again on appear and
            // whenever an offline run finishes; there is nothing on the server to sync.
            // Skeleton rows live inside the List/grid (see `listContent`/`gridContent`); the
            // empty/error message is an overlay fed the list's pull to refresh drag so it
            // rubber bands with it. One animation crossfades the whole state change.
            .overlay {
                ListStateOverlay(
                    phase: listPhase,
                    errorMessage: store.errorMessage,
                    emptyIcon: IconKit.availableOffline,
                    emptyMessage: L10n.Offline.tabEmpty,
                    noResultsMessage: L10n.EmptyState.noSearchMatches(store.searchQuery),
                    onRetry: { store.send(.refreshButtonTapped) }
                )
            }
            .animation(DSMotion.contentReveal, value: listPhase)
            .featureToast(error: store.actionErrorMessage)
            // The Mac table selects and sorts natively (column headers), so the tab adds no toolbar there.
            #if os(iOS)
                .toolbar {
                    selectSortToolbar(
                        isSelecting: store.isSelecting,
                        isAllSelected: isAllSelected,
                        isSelectAvailable: !store.downloads.isEmpty || !offlineStore.isEmpty,
                        isGridView: viewMode == .grid,
                        onSelectModeToggled: { store.send(.selectModeToggled) },
                        onSelectAllToggled: {
                            store.send(
                                isAllSelected
                                    ? .deselectAllTapped
                                    : .selectAllTapped(pinnedPaths: displayedPinned.map(\.root.path))
                            )
                        },
                        onCancel: { store.send(.selectModeToggled) },
                        onToggleViewMode: {
                            withAnimation(DSMotion.contentReveal) {
                                viewModeRaw = (viewMode == .list ? FileListViewMode.grid : .list).rawValue
                            }
                        }
                    ) {
                        Button {
                            isSortSheetPresented = true
                        } label: {
                            Label { Text(L10n.Common.sort) } icon: { IconKit.sort }
                        }
                    }
                }
            #endif
                .selectModeChrome(isSelecting: store.isSelecting)
                .prefersToolbarItemsInVerticalBar()
                .toolbar {
                    // The bar's actions only once something is picked, never greyed out over nothing.
                    if store.isSelecting, store.selectedCount > 0 {
                        OfflineSelectionToolbar(
                            selectedPinnedPaths: displayedPinned.map(\.root.path)
                                .filter(store.selectedPinnedPaths.contains),
                            selectedDownloadURLs: selectedDownloadURLs,
                            onRemoveFromOffline: { offlineStore.send(.removeSelectionTapped(paths: $0)) },
                            onDelete: { store.send(.bulkDeleteTapped) }
                        )
                    }
                }
                .dsSheet(isPresented: $isSortSheetPresented) {
                    SortSheet(
                        options: OfflineTabFeature.SortOption.allCases,
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
                .downloadDeleteAlerts(store: store)
                .offlineRemovalAlert(
                    offlineStore.removal,
                    onConfirm: {
                        offlineStore.send(.removeConfirmed, animation: DSMotion.listDiff)
                        if store.isSelecting {
                            store.send(.pinnedSelectionRemoved)
                        }
                    },
                    onCancel: { offlineStore.send(.removeCancelled) }
                )
                .dsSheet(item: renameItemBinding) { item in
                    NameInputSheet(
                        icon: IconKit.rename,
                        title: L10n.Browse.renameTitle,
                        placeholder: L10n.Browse.renameNamePlaceholder,
                        confirmTitle: L10n.Common.save,
                        initialName: item.fileName,
                        isBusy: false,
                        onConfirm: { store.send(.renameConfirmed($0)) },
                        onCancel: { store.send(.renameCancelled) }
                    )
                }
                .modifier(PreviewHostCover(
                    host: $store.scope(state: \.previewHost, action: \.previewHost),
                    zoom: zoom,
                    onViewShares: { store.send(.viewSharesFromPreviewTapped) }
                ))
                .fullScreenCover(item: $previewedDownload) { download in
                    ZoomingPreview(sourceID: download.id, context: zoom) {
                        FilePreviewContainerView(
                            fileURL: download.url,
                            errorMessage: nil,
                            onDismiss: { previewedDownload = nil },
                            onRename: {
                                previewedDownload = nil
                                store.send(.renameTapped(download))
                            },
                            onDelete: {
                                previewedDownload = nil
                                store.send(.deleteTapped(download))
                            }
                        )
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationHistoryTitle(L10n.Tab.offline)
                .task {
                    store.send(.onAppear)
                    offlineStore.send(.onAppear)
                }
                .onAppear { sourceVisibility.isScreenVisible = true }
                .onDisappear { sourceVisibility.isScreenVisible = false }
                // The account's folder can become known after the first listing (`me` answering, or the
                // recorded one read at an offline launch): list it again so its files show.
                .onChange(of: store.downloadScope) { _, scope in
                    if !scope.isEmpty {
                        store.send(.refreshButtonTapped)
                    }
                }
                .onChange(of: displayedPinned.map(\.root.path)) { _, paths in
                    if store.isSelecting {
                        store.send(.shownPinnedPathsChanged(paths))
                    }
                }
                .onOfflinePhaseChange(initial: true) { offlinePhase = $0 }
                // Only a run finishing while the tab is up reads it again; `.task` covers appearing.
                .onOfflinePhaseChange { phase in
                    if phase == .completed {
                        Task { @MainActor in offlineStore.send(.onAppear) }
                    }
                }
        } destination: { pushed in
            BrowseContentView(store: pushed)
        }
        .tint(Color.accent)
    }
}
