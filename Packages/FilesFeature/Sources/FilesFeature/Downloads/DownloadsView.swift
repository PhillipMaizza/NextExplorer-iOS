import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    /// Uneven redacted name / size / location widths so the skeleton doesn't line up as flat
    /// columns. Each row is `(name, "size • location")`.
    static let skeletonRows: [(name: String, subtitle: String)] = [
        (8, 4, 7), (13, 5, 4), (6, 3, 9), (11, 4, 5), (16, 5, 6),
        (7, 3, 8), (10, 4, 4), (5, 4, 10), (12, 5, 5), (9, 3, 7),
    ].map { name, size, loc in
        (String(repeating: "M", count: name),
         "\(String(repeating: "M", count: size)) • \(String(repeating: "M", count: loc))")
    }
}

struct DownloadsView: View {
    @Bindable var store: StoreOf<DownloadsFeature>
    @AppStorage(AppStorageKeys.downloadsViewMode) private var viewModeRaw = FileListViewMode.list.rawValue
    @State private var previewedDownload: LocalDownload?
    /// Native `.zoom` open + swipe-to-dismiss morph between a download cell and its preview.
    @Namespace private var previewTransition
    @State private var isSortSheetPresented = false
    /// How far the list is pulled below rest, fed to the empty/error overlay so it follows the
    /// pull-to-refresh rubber-band instead of staying pinned.
    @State private var pullOffset: CGFloat = 0
    @Environment(\.openURL) private var openURL

    private var viewMode: FileListViewMode {
        FileListViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var isAllSelected: Bool {
        !store.displayedDownloads.isEmpty && store.selectedDownloadIDs.count == store.displayedDownloads.count
    }

    private var selectedDownloadURLs: [URL] {
        store.downloads.filter { store.selectedDownloadIDs.contains($0.id) }.map(\.url)
    }

    /// The whole `Documents/Downloads` folder, for the top-right menu's generic "Open in
    /// Files" (as opposed to `filesAppURL(for:)`, which deep-links to one specific file).
    private var documentsDownloadsFolderURL: URL? {
        guard let documentsURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        guard var components = URLComponents(url: downloadsURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "shareddocuments"
        return components.url
    }

    /// The one screen state, derived from the store — skeleton until the first response lands
    /// (`store.phase`), then error / empty / no-results / the list. `phase.errorMessage` is
    /// non nil only on a first load failure with nothing to show, so it needs no empty guard.
    private var listPhase: ListPhase {
        .derive(
            hasError: store.errorMessage != nil,
            hasLoaded: store.phase.hasLoaded,
            isEmpty: store.downloads.isEmpty,
            hasNoResults: !store.searchQuery.isEmpty && store.displayedDownloads.isEmpty
        )
    }

    /// No op setters: each confirmation sheet is dismiss disabled and only closes through one
    /// of `DSAlertSheet`'s own buttons, which drive the reducer directly.
    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(get: { store.deleteConfirmationItem != nil }, set: { _ in })
    }

    private var deleteConfirmationTitle: String {
        guard let item = store.deleteConfirmationItem else { return L10n.Downloads.deleteConfirmTitle }
        return L10n.Downloads.deleteConfirmOne(item.fileName)
    }

    private var bulkDeleteConfirmationBinding: Binding<Bool> {
        Binding(get: { store.bulkDeleteConfirmationIsPresented }, set: { _ in })
    }

    private var bulkDeleteConfirmationTitle: String {
        L10n.Downloads.deleteConfirmMany(store.selectedDownloadIDs.count)
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
        // Bound once — `displayedDownloads` filters + sorts on every read, and the separator
        // checks below would otherwise re-derive it per row.
        let downloads = store.displayedDownloads
        let firstID = downloads.first?.id
        let lastID = downloads.last?.id
        ForEach(downloads) { download in
            DownloadListRow(
                store: store,
                download: download,
                namespace: previewTransition,
                openURL: openURL,
                isFirst: download.id == firstID,
                isLast: download.id == lastID,
                onPreview: { previewedDownload = download }
            )
        }
    }

    private var listContent: some View {
        DSGroupedList {
            if listPhase == .loading {
                skeletonRows
            } else {
                downloadRows
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
        // Only spring row diffs once the list is the content — during the skeleton→content
        // swap the outer `.animation(value: listPhase)` owns the cross-fade alone.
        .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedDownloads)
    }

    /// Redacted `FileRowView` stand-ins that sit in the *same* `List` as the real rows (never a
    /// separate scroll container — that fights the nav bar's large-title tracking). The shine
    /// is suppressed under Reduce Motion.
    @ViewBuilder
    private var skeletonRows: some View {
        ForEach(Array(Constants.skeletonRows.enumerated()), id: \.offset) { _, row in
            FileRowView(name: row.name, isDirectory: false, subtitle: row.subtitle, kind: "")
                .redacted(reason: .placeholder)
                .shimmering()
                .listRowBackground(Color.backgroundSecondary)
        }
    }

    @ViewBuilder
    private var skeletonCells: some View {
        ForEach(Array(Constants.skeletonRows.enumerated()), id: \.offset) { _, row in
            GridCellView(name: row.name, isDirectory: false, kind: "")
                .dsCard(padding: FileGridMetrics.cellPadding)
                .redacted(reason: .placeholder)
                .shimmering()
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: FileGridMetrics.columns, spacing: FileGridMetrics.spacing) {
                if listPhase == .loading {
                    skeletonCells
                } else {
                    downloadCells
                }
            }
            .padding(FileGridMetrics.spacing)
            .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedDownloads)
        }
        .backgroundGradient()
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
    }

    @ViewBuilder
    private var downloadCells: some View {
        ForEach(store.displayedDownloads) { download in
            DownloadGridCell(
                store: store,
                download: download,
                namespace: previewTransition,
                openURL: openURL,
                onPreview: { previewedDownload = download }
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewMode == .list {
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
                    title: store.isSelecting ? L10n.Common.selectedCount(store.selectedDownloadIDs.count) : L10n.Downloads.navigationTitle,
                    searchText: $store.searchQuery.sending(\.searchQueryChanged)
                )
            }
            .syncRefreshFeedback(errorMessage: store.errorMessage) {
                await store.send(.refreshButtonTapped).finish()
            }
            // Skeleton rows live inside the List/grid (see `listContent`/`gridContent`); the
            // empty/error message is an overlay fed the list's pull-to-refresh drag so it
            // rubber-bands with it. One animation cross-fades the whole state change.
            .overlay {
                ListStateOverlay(
                    phase: listPhase,
                    errorMessage: store.errorMessage,
                    emptyIcon: IconKit.download,
                    emptyMessage: L10n.Downloads.emptyList,
                    noResultsMessage: L10n.EmptyState.noSearchMatches(store.searchQuery),
                    pullOffset: pullOffset,
                    onRetry: { store.send(.refreshButtonTapped) }
                )
            }
            .animation(DSMotion.contentReveal, value: listPhase)
            .featureToast(error: store.actionErrorMessage)
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
                    },
                    macViewModes: .listAndGrid($viewModeRaw)
                ) {
                    if let documentsDownloadsFolderURL {
                        Button {
                            openURL(documentsDownloadsFolderURL)
                        } label: {
                            Label { Text(L10n.Downloads.actionOpenInFiles) } icon: { IconKit.folder }
                        }
                    }
                    Button {
                        isSortSheetPresented = true
                    } label: {
                        Label { Text(L10n.Common.sort) } icon: { IconKit.sort }
                    }
                }
            }
            .hapticFeedback(.selection, trigger: viewModeRaw)
            .hapticFeedback(.selection, trigger: store.isSelecting)
            .hidesTabBar(store.isSelecting)
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
            .sheet(isPresented: $isSortSheetPresented) {
                SortSheet(
                    options: DownloadsFeature.SortOption.allCases,
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
            .sheet(isPresented: deleteConfirmationBinding) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: deleteConfirmationTitle,
                    // Distinguishes this from every other delete confirmation in the app, which
                    // deletes on the server — this one only ever touches the local copy.
                    message: L10n.Downloads.deleteSingleMessage,
                    confirmTitle: L10n.Common.delete,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.deleteConfirmed) },
                    onDismiss: { store.send(.deleteCancelled) }
                )
            }
            .hapticFeedback(.warning, trigger: store.deleteConfirmationItem)
            .sheet(isPresented: bulkDeleteConfirmationBinding) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: bulkDeleteConfirmationTitle,
                    message: L10n.Downloads.deleteBulkMessage,
                    confirmTitle: L10n.Common.delete,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.bulkDeleteConfirmed) },
                    onDismiss: { store.send(.bulkDeleteCancelled) }
                )
            }
            .hapticFeedback(.warning, trigger: store.bulkDeleteConfirmationIsPresented)
            .sheet(item: renameItemBinding) { item in
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
            }
        }
        .tint(Color.accent)
    }
}

#Preview {
    DownloadsView(
        store: Store(initialState: DownloadsFeature.State()) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in
                [
                    LocalDownload(url: URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf"), fileName: "report.pdf", location: .documents, size: 245_000, modifiedDate: Date()),
                    LocalDownload(url: URL(fileURLWithPath: "/tmp/Caches/Downloads/vacation.jpg"), fileName: "vacation.jpg", location: .cache, size: 2_400_000, modifiedDate: Date().addingTimeInterval(-86400)),
                ]
            }
        }
    )
}

#Preview("Empty") {
    DownloadsView(
        store: Store(initialState: DownloadsFeature.State()) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in [] }
        }
    )
}

#Preview("Error") {
    DownloadsView(
        store: Store(initialState: DownloadsFeature.State()) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in throw NSError(domain: "test", code: 1) }
        }
    )
}
