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
    /// A finished offline run changes what the tab lists, so it is read again.
    @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) private var offlineProgress = OfflineDownloadProgress()
    /// The same list or grid choice as Browse and Favorites, so a folder opened from this tab keeps it.
    @AppStorage(AppStorageKeys.browseViewMode) private var viewModeRaw = FileListViewMode.list.rawValue
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue

    private var thumbnailSize: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    @State private var previewedDownload: LocalDownload?
    /// Native `.zoom` open + swipe-to-dismiss morph between a download cell and its preview.
    @Namespace private var previewTransition
    @State private var isSortSheetPresented = false

    /// Pinned items and files saved earlier, the whole tab's footprint on this device.
    private var usedBytes: Int64 {
        offlineStore.totalBytes + store.downloads.reduce(Int64(0)) { $0 + $1.size }
    }

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
        !store.displayedDownloads.isEmpty && store.selectedDownloadIDs.count == store.displayedDownloads.count
    }

    private var selectedDownloadURLs: [URL] {
        store.downloads.filter { store.selectedDownloadIDs.contains($0.id) }.map(\.url)
    }

    /// The one screen state, derived from the store: skeleton until the first response lands
    /// (`store.phase`), then error / empty / no-results / the list. `phase.errorMessage` is
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
        // checks below would otherwise re-derive it per row.
        let downloads = store.displayedDownloads
        let firstID = downloads.first?.id
        let lastID = downloads.last?.id
        ForEach(downloads) { download in
            DownloadListRow(
                store: store,
                download: download,
                namespace: previewTransition,
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
                    OfflinePinnedSection(store: offlineStore, usages: displayedPinned, favorites: favorites) { root in
                        store.send(.pinnedItemTapped(root))
                    }
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
        .backgroundGradient()
        .dismissKeyboardOnTap()
        // Only spring row diffs once the list is the content: during the skeleton→content
        // swap the outer `.animation(value: listPhase)` owns the cross-fade alone.
        .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedDownloads)
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: FileGridMetrics.columns(for: thumbnailSize), spacing: FileGridMetrics.spacing) {
                if listPhase == .loading {
                    SkeletonGridCells(entries: Constants.skeletonEntries)
                } else {
                    OfflinePinnedGridCells(
                        store: offlineStore,
                        usages: displayedPinned,
                        favorites: favorites
                    ) { root in
                        store.send(.pinnedItemTapped(root))
                    }
                    downloadCells
                }
            }
            .padding(FileGridMetrics.spacing)
            .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedDownloads)
        }
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
                namespace: previewTransition,
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
            // Full-bleed *before* `.overlay` below: without a frame fixed to the screen size
            // up front, the List's own intrinsic size can lag a frame behind on first
            // appearance, and the overlay (default-centered on whatever frame it currently
            // sees) visibly slides from that transient small frame to the real one.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                PinnedTitleSearchHeader(
                    title: store.isSelecting
                        ? L10n.Common.selectedCount(store.selectedDownloadIDs.count)
                        : L10n.Tab.offline,
                    searchText: $store.searchQuery.sending(\.searchQueryChanged),
                    shouldFadeIntoContent: !isMacTable
                )
            }
            // No refresh control: the tab lists what is on the device, read again on appear and
            // whenever an offline run finishes; there is nothing on the server to sync.
            // Skeleton rows live inside the List/grid (see `listContent`/`gridContent`); the
            // empty/error message is an overlay fed the list's pull-to-refresh drag so it
            // rubber-bands with it. One animation cross-fades the whole state change.
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if listPhase == .content, usedBytes > 0 {
                    OfflineStorageSummary(bytes: usedBytes)
                }
            }
            .animation(DSMotion.contentReveal, value: listPhase)
            .featureToast(error: store.actionErrorMessage)
            // The Mac table selects and sorts natively (column headers), so the tab adds no toolbar there.
            #if os(iOS)
                .toolbar {
                    selectSortToolbar(
                        isSelecting: store.isSelecting,
                        isAllSelected: isAllSelected,
                        isSelectAvailable: !store.downloads.isEmpty,
                        isGridView: viewMode == .grid,
                        onSelectModeToggled: { store.send(.selectModeToggled) },
                        onSelectAllToggled: { store.send(isAllSelected ? .deselectAllTapped : .selectAllTapped) },
                        onCancel: { store.send(.selectModeToggled) },
                        onToggleViewMode: {
                            withAnimation {
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
                .hapticFeedback(.selection, trigger: viewModeRaw)
                .hapticFeedback(.selection, trigger: store.isSelecting)
                .hidesTabBar(store.isSelecting)
                .prefersToolbarItemsInVerticalBar()
                .toolbar {
                    if store.isSelecting {
                        ToolbarItem(placement: .bottomBar) {
                            Spacer()
                        }
                        ToolbarItem(placement: .bottomBar) {
                            ShareLink(items: selectedDownloadURLs) {
                                IconKit.share
                            }
                            .accessibilityLabel(L10n.Common.share)
                            .disabled(store.selectedDownloadIDs.isEmpty)
                        }
                        ToolbarItem(placement: .bottomBar) {
                            SelectionToolbarButton(
                                icon: IconKit.delete,
                                role: .destructive,
                                tint: .negative,
                                accessibilityLabel: L10n.Common.delete,
                                isDisabled: store.selectedDownloadIDs.isEmpty
                            ) {
                                store.send(.bulkDeleteTapped)
                            }
                        }
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
                        onSelectOption: { store.send(.sortOptionChanged($0)) },
                        onSelectDirection: { store.send(.sortDirectionChanged($0)) },
                        onDismiss: { isSortSheetPresented = false }
                    )
                }
                .downloadDeleteAlerts(store: store)
                .offlineRemovalAlert(
                    offlineStore.removal,
                    onConfirm: { offlineStore.send(.removeConfirmed) },
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
                    onViewShares: { store.send(.viewSharesFromPreviewTapped) }
                ))
                .fullScreenCover(item: $previewedDownload) { download in
                    PreviewZoomContainer(sourceID: download.id, namespace: previewTransition) {
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
                // Title lives in the pinned header (see `PinnedTitleSearchHeader`); the nav bar keeps
                // only its actions.
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    store.send(.onAppear)
                    offlineStore.send(.onAppear)
                }
                // The account's folder can become known after the first listing (`me` answering, or the
                // recorded one read at an offline launch): list it again so its files show.
                .onChange(of: store.downloadScope) { _, scope in
                    if !scope.isEmpty {
                        store.send(.refreshButtonTapped)
                    }
                }
                .onChange(of: offlineProgress.phase) { _, phase in
                    if phase == .completed {
                        Task { @MainActor in offlineStore.send(.onAppear) }
                    }
                }
        } destination: { pushed in
            BrowseContentView(store: pushed)
                .environment(\.showsOfflineBadges, false)
                .navigationTitle("")
        }
        .tint(Color.accent)
    }
}
