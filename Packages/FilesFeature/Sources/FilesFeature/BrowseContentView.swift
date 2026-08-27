import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

private enum BrowseViewMode: String {
    case list, grid
}

private enum Constants {
    static let emptyStateSpacing: CGFloat = .space8
    static let emptyStateIconSize: CGFloat = .superIcon
    static let gridSpacing: CGFloat = .space16
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
    static let overlayCrossfadeDuration: Double = 0.2
}

/// The list body shown at every depth of Browse: root and every pushed subfolder
/// render this same view, scoped to their own `BrowseFeature` store. The list/grid
/// choice is a per-device display preference, not per-folder state, so it's stored
/// directly here rather than threaded through `BrowseFeature.State`.
struct BrowseContentView: View {
    @Bindable var store: StoreOf<BrowseFeature>
    @AppStorage("browseViewMode") private var viewModeRaw = BrowseViewMode.list.rawValue
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue
    @AppStorage("removeArchiveAfterDownload") private var removeArchiveAfterDownload = false
    @State private var isSortSheetPresented = false
    /// The rename alert's in-progress text: kept as plain view state rather than routed
    /// through the store, since a `.alert` `TextField` bound via a TCA `.sending` binding
    /// didn't reliably propagate keystrokes back out. Seeded from `renameSheetItem` when
    /// the alert is presented; `renameConfirmed` is sent this value directly.
    @State private var renameDraft = ""
    @State private var toastMessage: DSToastMessage?
    /// The item whose "Create Share Link" sheet is open (from the context menu or the
    /// selection toolbar). Local view state, not routed through `BrowseFeature` — the sheet
    /// owns its own ad-hoc `CreateShareLinkFeature` store.
    @State private var shareTarget: FileItem?
    /// Flipped once a pull-to-refresh completes, purely as a `.hapticFeedback` trigger — the
    /// value itself is meaningless, only the fact that it just changed matters.
    @State private var didFinishRefreshing = false

    private var viewMode: BrowseViewMode {
        BrowseViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var thumbnailSize: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize.gridItemMinWidth), spacing: Constants.gridSpacing)]
    }

    /// Pre-filters kinds `rowTapped` would just silently no-op on (or, for unsupported video
    /// containers, previously opened a full-screen "can't play this" view for) — a toast reads
    /// better than either a dead tap or interrupting with a whole screen.
    private func handleTap(_ item: FileItem) {
        guard !item.isDirectory else {
            store.send(.rowTapped(item))
            return
        }
        guard !item.isUnsupportedForPreview else {
            toastMessage = DSToastMessage(icon: IconKit.warning, text: "Unsupported file type")
            return
        }
        store.send(.rowTapped(item))
    }

    var body: some View {
        browsingContent
            .sheet(item: infoPhaseBinding) { phase in
                infoSheetContent(for: phase)
            }
            .fullScreenCover(item: previewItemBinding) { item in
                previewContent(for: item)
            }
            .sheet(item: $shareTarget) { item in
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
                    }
                )
            }
            .dsToast($toastMessage, extraBottomInset: breadcrumbBarClearance)
            .dsToast(progressToastBinding, extraBottomInset: breadcrumbBarClearance)
            // `fileActionErrorMessage` (rename/delete/extract/compress failures) was set on
            // `State` but never actually read by any view — silently swallowed. Mirrored into
            // the same toast the unsupported-file-type warning uses.
            .onChange(of: store.fileActionErrorMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = DSToastMessage(icon: IconKit.warning, text: newValue)
            }
            .onChange(of: store.downloadSuccessMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(newValue, actionTitle: "Open") {
                    store.send(.delegate(.openDownloadsTapped))
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
            if viewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Color.accent)
        .searchable(
            text: $store.searchQuery.sending(\.searchQueryChanged),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        .searchScopes($store.searchScope.sending(\.searchScopeChanged)) {
            ForEach(BrowseFeature.SearchScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .refreshable {
            await store.send(.refreshButtonTapped).finish()
            didFinishRefreshing.toggle()
        }
        .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.errorMessage == nil }
        .hapticFeedback(.error, trigger: store.errorMessage) { _, newValue in newValue != nil }
        .overlay {
            overlayStateContent
                .id(overlayState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayState)
        .toolbar {
            selectSortToolbar(
                isSelecting: store.isSelecting,
                isAllSelected: isAllSelected,
                isSelectAvailable: !store.isSearching && !store.displayedItems.isEmpty,
                isGridView: viewMode == .grid,
                onSelectModeToggled: { store.send(.selectModeToggled) },
                onSelectAllToggled: { store.send(isAllSelected ? .deselectAllTapped : .selectAllTapped) },
                onCancel: { store.send(.selectModeToggled) },
                onToggleViewMode: {
                    withAnimation {
                        viewModeRaw = (viewMode == .list ? BrowseViewMode.grid : .list).rawValue
                    }
                }
            ) {
                Button {
                    isSortSheetPresented = true
                } label: {
                    Label { Text("Sort") } icon: { IconKit.sort }
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
                if let singleSelectedItem, store.access?.canWrite ?? false {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            store.send(.renameTapped(singleSelectedItem))
                        } label: {
                            IconKit.rename
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                if let singleSelectedItem, store.access?.canShare ?? false {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            shareTarget = singleSelectedItem
                        } label: {
                            IconKit.shareLink
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                if isFavoriteActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            store.send(.bulkFavoriteTapped)
                        } label: {
                            isEntireSelectionAlreadyFavorited ? IconKit.starFill : IconKit.star
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                if isDownloadActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            store.send(.bulkDownloadTapped(.documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                        } label: {
                            IconKit.download
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                if isDeleteActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            store.send(.bulkDeleteTapped)
                        } label: {
                            IconKit.delete.foregroundStyle(Color.negative)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.selectedItemIDs
        )
        .alert(bulkDeleteConfirmationTitle, isPresented: bulkDeleteConfirmationBinding) {
            Button("Delete", role: .destructive) { store.send(.bulkDeleteConfirmed) }
            Button("Cancel", role: .cancel) { store.send(.bulkDeleteCancelled) }
        } message: {
            Text("This can't be undone.")
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
        .alert("Rename", isPresented: isRenamingBinding) {
            TextField("Name", text: $renameDraft)
                .autocorrectionDisabled()
            // A plain, non-accent color for Cancel: `.tint(nil)` doesn't reset an alert
            // button back to the system default (it still inherits the ambient accent), so
            // an explicit concrete color is needed to actually look different from Save.
            Button("Cancel", role: .cancel) { store.send(.renameCancelled) }
                .tint(.primaryDS)
            Button("Save") { store.send(.renameConfirmed(renameDraft)) }
        }
        .onChange(of: store.renameSheetItem) { _, item in
            if let item { renameDraft = item.name }
        }
        // `.alert`, not `.confirmationDialog`: a confirmationDialog presents as a popover
        // anchored to some ambient source view on the `.pad` idiom (this app also targets
        // iPad) rather than a full-width bottom sheet, and picked an unrelated anchor point
        // instead of the actual long-pressed row. `.alert` is always a centered modal
        // regardless of idiom, so there's no anchor to get wrong.
        .alert(deleteConfirmationTitle, isPresented: isDeletingBinding) {
            Button("Delete", role: .destructive) { store.send(.deleteConfirmed) }
            Button("Cancel", role: .cancel) { store.send(.deleteCancelled) }
        } message: {
            Text("This can't be undone.")
        }
        .hapticFeedback(.warning, trigger: store.deleteConfirmationItem)
    }

    private var previewItemBinding: Binding<FileItem?> {
        Binding(
            get: { store.previewItem },
            set: { if $0 == nil { store.send(.previewDismissed) } }
        )
    }

    /// Read-only from the store's perspective: `fileActionProgressMessage` clears itself once
    /// the extract/compress effect resolves, so there's nothing for the view to write back —
    /// the toast has no auto-dismiss timer to fire early either (`DSToastMessage.progress`
    /// sets `isPersistent`), so the setter is genuinely never called in practice.
    private var progressToastBinding: Binding<DSToastMessage?> {
        Binding(
            get: { store.fileActionProgressMessage.map { DSToastMessage.progress($0) } },
            set: { _ in }
        )
    }

    @ViewBuilder
    private func previewContent(for item: FileItem) -> some View {
        if item.isStreamableMedia, let url = FilesClient.previewURL(serverURL: store.serverURL, item: item) {
            // Guaranteed `isNativelyPlayable` by this point — unsupported containers/codecs
            // are caught by the toast in `handleTap`, before `rowTapped` is ever sent.
            StreamingPreviewView(
                item: item,
                url: url,
                serverURL: store.serverURL,
                onDismiss: { store.send(.previewDismissed) },
                onShare: (store.access?.canShare ?? false) ? {
                    store.send(.previewDismissed)
                    shareTarget = item
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.deleteTapped(item))
                } : nil
            )
        } else if item.isBrowsableArchive {
            ArchiveBrowserView(item: item, serverURL: store.serverURL, onDismiss: { store.send(.previewDismissed) })
        } else if (item.isImage || item.isRawImage) && !item.isSVG {
            ImageGalleryView(
                items: store.displayedItems.filter { ($0.isImage || $0.isRawImage) && !$0.isSVG },
                initialItem: item,
                serverURL: store.serverURL,
                onDismiss: { store.send(.previewDismissed) },
                onShare: (store.access?.canShare ?? false) ? { current in
                    store.send(.previewDismissed)
                    shareTarget = current
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? { current in
                    store.send(.previewDismissed)
                    store.send(.downloadTapped(current, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? { current in
                    store.send(.previewDismissed)
                    store.send(.deleteTapped(current))
                } : nil
            )
        } else if item.isPreviewableViaDownload {
            FilePreviewContainerView(
                fileURL: store.previewFileURL,
                errorMessage: store.previewErrorMessage,
                onDismiss: { store.send(.previewDismissed) },
                onShareLink: (store.access?.canShare ?? false) ? {
                    store.send(.previewDismissed)
                    shareTarget = item
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.deleteTapped(item))
                } : nil
            )
        } else {
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
                onDismiss: { store.send(.previewDismissed) }
            )
        }
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
            set: { if $0 == nil { store.send(.infoDismissed) } }
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
                errorMessage: store.infoErrorMessage,
                onDismiss: { store.send(.infoDismissed) }
            )
        }
    }

    private var isRenamingBinding: Binding<Bool> {
        Binding(
            get: { store.renameSheetItem != nil },
            set: { if !$0 { store.send(.renameCancelled) } }
        )
    }

    private var isDeletingBinding: Binding<Bool> {
        Binding(
            get: { store.deleteConfirmationItem != nil },
            set: { if !$0 { store.send(.deleteCancelled) } }
        )
    }

    private var deleteConfirmationTitle: String {
        guard let item = store.deleteConfirmationItem else { return "Delete?" }
        return "Delete \u{201C}\(item.name)\u{201D}?"
    }

    private var isAllSelected: Bool {
        !store.displayedItems.isEmpty && store.selectedItemIDs.count == store.displayedItems.count
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

    private var bulkDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { store.bulkDeleteConfirmationIsPresented },
            set: { if !$0 { store.send(.bulkDeleteCancelled) } }
        )
    }

    private var bulkDeleteConfirmationTitle: String {
        "Delete \(store.selectedItemIDs.count) item\(store.selectedItemIDs.count == 1 ? "" : "s")?"
    }

    @ViewBuilder
    private func fileActionsContextMenu(for item: FileItem) -> some View {
        // Explicit `.tint`: this whole view is under `.tint(Color.accent)`, which would
        // otherwise cascade into the menu and color every icon/label gold instead of the
        // system's normal label color — only Delete should stand out, in red.
        Button {
            store.send(.infoTapped(item))
        } label: {
            Label { Text("Get Info") } icon: { IconKit.info }
        }
        .tint(.primaryDS)
        if store.access?.canWrite ?? false {
            Button {
                store.send(.renameTapped(item))
            } label: {
                Label { Text("Rename") } icon: { IconKit.rename }
            }
            .tint(.primaryDS)
        }
        if store.access?.canWrite ?? false {
            // Extract only offers `.zip` — the server's own extract route 415s anything else
            // ("Only .zip archives are supported"), `.rar` included despite this app being
            // able to browse rar contents client-side.
            if item.kind.lowercased() == "zip" {
                Button {
                    store.send(.extractZipTapped(item))
                } label: {
                    Label { Text("Extract") } icon: { IconKit.extract }
                }
                .tint(.primaryDS)
            }
            Button {
                store.send(.compressTapped(item))
            } label: {
                Label { Text("Compress") } icon: { IconKit.archiveDocument }
            }
            .tint(.primaryDS)
        }
        if store.access?.canDownload ?? false {
            Button {
                store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
            } label: {
                Label { Text("Download") } icon: { IconKit.download }
            }
            .tint(.primaryDS)
        }
        // Only folders can be favorited — the server 400s on anything else.
        if item.isDirectory {
            Button {
                store.send(.favoriteToggleButtonTapped(item))
            } label: {
                if store.favoritePaths.contains(item.id) {
                    Label { Text("Remove from Favorites") } icon: { IconKit.starFill }
                } else {
                    Label { Text("Add to Favorites") } icon: { IconKit.star }
                }
            }
            .tint(.primaryDS)
        }
        if store.access?.canShare ?? false {
            Button {
                shareTarget = item
            } label: {
                Label { Text("Share") } icon: { IconKit.shareLink }
            }
            .tint(.primaryDS)
        }
        if store.access?.canDelete ?? false {
            Button(role: .destructive) {
                store.send(.deleteTapped(item))
            } label: {
                Label { Text("Delete") } icon: { IconKit.delete }
            }
            .tint(.negative)
        }
    }

    /// Which branch of `overlayStateContent` is currently showing — a plain discriminant so
    /// the overlay can cross-fade between states instead of hard-cutting between them.
    private enum OverlayState: Hashable {
        case none, loading, error, empty, searchingEverywhere, noResults
    }

    private var overlayState: OverlayState {
        if store.isLoading && store.items.isEmpty {
            .loading
        } else if store.errorMessage != nil {
            .error
        } else if !store.isSearching && store.displayedItems.isEmpty {
            .empty
        } else if store.isSearching && store.searchScope == .everywhere && store.isSearchingEverywhere {
            .searchingEverywhere
        } else if store.isSearching, let results = store.displayedSearchResults, results.isEmpty {
            .noResults
        } else {
            .none
        }
    }

    @ViewBuilder
    private var overlayStateContent: some View {
        switch overlayState {
        case .loading, .searchingEverywhere:
            ProgressView()
                .transition(.opacity)
        case .error:
            if let errorMessage = store.errorMessage {
                EmptyStateView(icon: IconKit.warning, message: errorMessage) {
                    store.send(.refreshButtonTapped)
                }
                    .transition(.opacity)
            }
        case .empty:
            EmptyStateView(icon: IconKit.folder, message: "This folder is empty.")
                .transition(.opacity)
        case .noResults:
            noResultsState
                .transition(.opacity)
        case .none:
            EmptyView()
        }
    }

    private var listContent: some View {
        List {
            if store.isSearching {
                searchResultRows
            } else {
                folderItemRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
        .safeAreaPadding(.bottom, breadcrumbBarClearance)
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.displayedItems
        )
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.displayedSearchResults
        )
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Constants.gridSpacing) {
                if store.isSearching {
                    ForEach(store.displayedSearchResults ?? []) { result in
                        Button {
                            store.send(.searchResultTapped(result))
                        } label: {
                            GridCellView(name: result.name, isDirectory: result.isDirectory, isFavorite: store.favoritePaths.contains(result.id), kind: result.kind)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .disabled(!result.isDirectory)
                    }
                } else {
                    ForEach(store.displayedItems) { item in
                        Button {
                            if store.isSelecting {
                                store.send(.itemSelectionToggled(item.id))
                            } else {
                                handleTap(item)
                            }
                        } label: {
                            GridCellView(
                                item: item,
                                isFavorite: store.favoritePaths.contains(item.id),
                                serverURL: store.serverURL,
                                showThumbnails: store.preferences.showThumbnails,
                                iconSize: thumbnailSize.iconSize
                            )
                            .overlay(alignment: .topLeading) {
                                if store.isSelecting {
                                    selectionIndicator(isSelected: store.selectedItemIDs.contains(item.id))
                                }
                            }
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .hapticFeedback(.selection, trigger: store.selectedItemIDs.contains(item.id))
                        .contextMenu {
                            if !store.isSelecting {
                                fileActionsContextMenu(for: item)
                            }
                        }
                    }
                }
            }
            .padding(Constants.gridSpacing)
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: store.displayedItems
            )
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: store.displayedSearchResults
            )
        }
        .background(Color.backgroundPrimary)
        .safeAreaPadding(.bottom, breadcrumbBarClearance)
    }

    /// The breadcrumb bar is only ever visible on a pushed screen — the root's
    /// `directoryPath` is always empty — so this view can tell whether it needs to reserve
    /// clearance for it purely from its own state, without threading the bar's visibility
    /// down from `BrowseTabView`.
    private var breadcrumbBarClearance: CGFloat {
        store.directoryPath.isEmpty ? 0 : BrowseBreadcrumbBarMetrics.height
    }

    @ViewBuilder
    private var folderItemRows: some View {
        ForEach(store.displayedItems) { item in
            Button {
                if store.isSelecting {
                    store.send(.itemSelectionToggled(item.id))
                } else {
                    handleTap(item)
                }
            } label: {
                HStack(spacing: .space12) {
                    if store.isSelecting {
                        selectionIndicator(isSelected: store.selectedItemIDs.contains(item.id))
                    }
                    FileRowView(
                        item: item,
                        isFavorite: store.favoritePaths.contains(item.id),
                        serverURL: store.serverURL,
                        showThumbnails: store.preferences.showThumbnails
                    )
                }
            }
            .buttonStyle(DSHapticButtonStyle())
            .hapticFeedback(.selection, trigger: store.selectedItemIDs.contains(item.id))
            .contextMenu {
                if !store.isSelecting {
                    fileActionsContextMenu(for: item)
                }
            }
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing) {
                if !store.isSelecting {
                    if store.access?.canDelete ?? false {
                        Button {
                            store.send(.deleteTapped(item))
                        } label: {
                            IconKit.delete
                        }
                        .tint(.negative)
                    }
                    // Only folders can be favorited — the server 400s on anything else.
                    if item.isDirectory {
                        Button {
                            store.send(.favoriteToggleButtonTapped(item))
                        } label: {
                            store.favoritePaths.contains(item.id) ? IconKit.starFill : IconKit.star
                        }
                        .tint(.accent)
                    }
                    if store.access?.canWrite ?? false {
                        Button {
                            store.send(.renameTapped(item))
                        } label: {
                            IconKit.rename
                        }
                        .tint(.positive)
                    }
                }
            }
            .listRowSeparator(item.id == store.displayedItems.first?.id ? .hidden : .visible, edges: .top)
            .listRowSeparator(item.id == store.displayedItems.last?.id ? .hidden : .visible, edges: .bottom)
        }
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        (isSelected ? IconKit.checkmarkCircleFill : IconKit.radioUnselected)
            .resizable()
            .scaledToFit()
            .foregroundStyle(isSelected ? Color.accent : Color.secondaryDS)
            .frame(width: .iconMedium, height: .iconMedium)
            .symbolEffect(.bounce, value: isSelected)
            .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private var searchResultRows: some View {
        let results = store.displayedSearchResults ?? []
        ForEach(results) { result in
            Button {
                store.send(.searchResultTapped(result))
            } label: {
                FileRowView(name: result.name, isDirectory: result.isDirectory, subtitle: result.matchLine, isFavorite: store.favoritePaths.contains(result.id), kind: result.kind)
            }
            .buttonStyle(DSHapticButtonStyle())
            .disabled(!result.isDirectory)
            .listRowBackground(Color.clear)
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
            Text("No matches for \u{201C}\(store.searchQuery)\u{201D}.")
                .type(.body1(.semibold), style: .secondary)
            if store.searchScope == .thisFolder {
                DSButton("Search everywhere",
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

#Preview("BrowseContentView") {
    NavigationStack {
        BrowseContentView(
            store: Store(
                initialState: BrowseFeature.State(
                    serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                    directoryPath: "",
                    title: "Browse"
                )
            ) {
                BrowseFeature()
            } withDependencies: {
                $0.filesClient = .previewValue
            }
        )
        .navigationTitle("Browse")
    }
}

