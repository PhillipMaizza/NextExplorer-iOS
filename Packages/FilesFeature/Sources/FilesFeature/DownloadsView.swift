import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum DownloadsViewMode: String {
    case list, grid
}

private enum Constants {
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
    static let overlayCrossfadeDuration: Double = 0.2
    static let gridSpacing: CGFloat = .space16
    /// Inset between a grid tile's content and its `backgroundSecondary` card edge, matching
    /// `BrowseContentView`.
    static let gridCellPadding: CGFloat = .space12
}

struct DownloadsView: View {
    @Bindable var store: StoreOf<DownloadsFeature>
    @AppStorage(AppStorageKeys.downloadsViewMode) private var viewModeRaw = DownloadsViewMode.list.rawValue
    @State private var previewedDownload: LocalDownload?
    @State private var isSortSheetPresented = false
    /// Flipped once a pull-to-refresh completes, purely as a `.hapticFeedback` trigger — the
    /// value itself is meaningless, only the fact that it just changed matters.
    @State private var didFinishRefreshing = false
    @Environment(\.openURL) private var openURL

    private var viewMode: DownloadsViewMode {
        DownloadsViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 100), spacing: Constants.gridSpacing)]
    }

    private var isAllSelected: Bool {
        !store.displayedDownloads.isEmpty && store.selectedDownloadIDs.count == store.displayedDownloads.count
    }

    private var selectedDownloadURLs: [URL] {
        store.downloads.filter { store.selectedDownloadIDs.contains($0.id) }.map(\.url)
    }

    /// Deep-links the Files app straight to this file (`LSSupportsOpeningDocumentsInPlace`/
    /// `UIFileSharingEnabled`, set in Info.plist, expose the app's Documents folder there) —
    /// `nil` for `.cache`-location downloads, which are app-private and never show up in
    /// Files regardless of scheme.
    private func filesAppURL(for download: LocalDownload) -> URL? {
        guard download.location == .documents else { return nil }
        guard var components = URLComponents(url: download.url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "shareddocuments"
        return components.url
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

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func subtitle(for download: LocalDownload) -> String {
        "\(Self.byteFormatter.string(fromByteCount: download.size)) • \(download.location.title)"
    }

    private var overlayPhase: ListStateOverlay.Phase {
        if store.isLoading && store.downloads.isEmpty {
            .loading
        } else if store.errorMessage != nil {
            .error
        } else if store.downloads.isEmpty {
            .empty
        } else if !store.searchQuery.isEmpty && store.displayedDownloads.isEmpty {
            .noResults
        } else {
            .none
        }
    }

    // No op setters: each confirmation sheet is dismiss disabled and only closes through one
    // of `DSAlertSheet`'s own buttons, which drive the reducer directly.
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
        Binding(get: { store.renameItem }, set: { if $0 == nil { store.send(.renameCancelled) } })
    }

    private func handleTap(_ download: LocalDownload) {
        if store.isSelecting {
            store.send(.itemSelectionToggled(download.id))
        } else {
            previewedDownload = download
        }
    }

    @ViewBuilder
    private func rowContextMenu(for download: LocalDownload) -> some View {
        if let filesAppURL = filesAppURL(for: download) {
            Button {
                openURL(filesAppURL)
            } label: {
                Label { Text(L10n.Downloads.actionOpenInFiles) } icon: { IconKit.folder }
            }
            .tint(.primaryDS)
            Divider()
        }
        ShareLink(item: download.url) {
            Label { Text(L10n.Common.share) } icon: { IconKit.share }
        }
        .tint(.primaryDS)
        Button {
            store.send(.renameTapped(download))
        } label: {
            Label { Text(L10n.Browse.actionRename) } icon: { IconKit.rename }
        }
        .tint(.primaryDS)
        Button(role: .destructive) {
            store.send(.deleteTapped(download))
        } label: {
            Label { Text(L10n.Common.delete) } icon: { IconKit.delete }
        }
        .tint(.negative)
    }

    @ViewBuilder
    private var downloadRows: some View {
        // Bound once — `displayedDownloads` filters + sorts on every read, and the separator
        // checks below would otherwise re-derive it per row.
        let downloads = store.displayedDownloads
        let firstID = downloads.first?.id
        let lastID = downloads.last?.id
        ForEach(downloads) { download in
            Button {
                handleTap(download)
            } label: {
                HStack(spacing: .space12) {
                    if store.isSelecting {
                        DSSelectionIndicator(isSelected: store.selectedDownloadIDs.contains(download.id))
                    }
                    FileRowView(name: download.fileName, isDirectory: false, subtitle: subtitle(for: download), kind: (download.fileName as NSString).pathExtension)
                }
            }
            .buttonStyle(DSHapticButtonStyle())
            .listRowBackground(Color.backgroundSecondary)
            .swipeActions(edge: .trailing) {
                if !store.isSelecting {
                    // No `role: .destructive` — a destructive-role swipe button makes `List`
                    // collapse the row itself the moment it's tapped, before the confirmation
                    // alert is answered. On Cancel the row is already gone, and the next data
                    // update crashes the collection view with a section-count mismatch.
                    Button {
                        store.send(.deleteTapped(download))
                    } label: {
                        IconKit.delete
                    }
                    .tint(.negative)
                    Button {
                        store.send(.renameTapped(download))
                    } label: {
                        IconKit.rename
                    }
                    .tint(.positive)
                    // The plain system share sheet — local downloads have no server-side
                    // sharing semantics to worry about, unlike Browse's items.
                    ShareLink(item: download.url) {
                        IconKit.share
                    }
                    .tint(.accent)
                }
            }
            .contextMenu {
                if !store.isSelecting {
                    rowContextMenu(for: download)
                }
            }
            .listRowSeparator(download.id == firstID ? .hidden : .visible, edges: .top)
            .listRowSeparator(download.id == lastID ? .hidden : .visible, edges: .bottom)
        }
    }

    private var listContent: some View {
        List {
            downloadRows
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.displayedDownloads
        )
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Constants.gridSpacing) {
                ForEach(store.displayedDownloads) { download in
                    Button {
                        handleTap(download)
                    } label: {
                        GridCellView(name: download.fileName, isDirectory: false, kind: (download.fileName as NSString).pathExtension)
                            .dsCard(padding: Constants.gridCellPadding)
                            .overlay(alignment: .topLeading) {
                                if store.isSelecting {
                                    DSSelectionIndicator(isSelected: store.selectedDownloadIDs.contains(download.id))
                                }
                            }
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .hapticFeedback(.selection, trigger: store.selectedDownloadIDs.contains(download.id))
                    .contextMenu {
                        if !store.isSelecting {
                            rowContextMenu(for: download)
                        }
                    }
                }
            }
            .padding(Constants.gridSpacing)
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: store.displayedDownloads
            )
        }
        .backgroundGradient()
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
            .searchable(
                text: $store.searchQuery.sending(\.searchQueryChanged),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.Common.search
            )
            .refreshable {
                await store.send(.refreshButtonTapped).finish()
                didFinishRefreshing.toggle()
            }
            .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.errorMessage == nil }
            .hapticFeedback(.error, trigger: store.errorMessage) { _, newValue in newValue != nil }
            .overlay {
                ListStateOverlay(
                    phase: overlayPhase,
                    errorMessage: store.errorMessage,
                    emptyIcon: IconKit.download,
                    emptyMessage: L10n.Downloads.emptyList,
                    noResultsMessage: L10n.EmptyState.noSearchMatches(store.searchQuery),
                    onRetry: { store.send(.refreshButtonTapped) }
                )
            }
            .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayPhase)
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
                            viewModeRaw = (viewMode == .list ? DownloadsViewMode.grid : .list).rawValue
                        }
                    }
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
            .toolbar(store.isSelecting ? .hidden : .automatic, for: .tabBar)
            .toolbar {
                if store.isSelecting {
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        ShareLink(items: selectedDownloadURLs) {
                            IconKit.share
                        }
                        .disabled(store.selectedDownloadIDs.isEmpty)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            store.send(.bulkDeleteTapped)
                        } label: {
                            IconKit.delete.foregroundStyle(Color.negative)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .disabled(store.selectedDownloadIDs.isEmpty)
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
            .navigationTitle(store.isSelecting ? L10n.Common.selectedCount(store.selectedDownloadIDs.count) : L10n.Downloads.navigationTitle)
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
            $0.localDownloadStore.list = {
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
            $0.localDownloadStore.list = { [] }
        }
    )
}

#Preview("Error") {
    DownloadsView(
        store: Store(initialState: DownloadsFeature.State()) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { throw NSError(domain: "test", code: 1) }
        }
    )
}
