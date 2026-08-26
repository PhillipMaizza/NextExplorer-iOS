import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

private enum BrowseViewMode: String {
    case list, grid
}

private enum Constants {
    static let emptyStateSpacing: CGFloat = .space8
    static let emptyStateIconSize: CGFloat = .superIcon
    static let gridItemMinWidth: CGFloat = 100
    static let gridColumns = [GridItem(.adaptive(minimum: gridItemMinWidth), spacing: .space16)]
    static let gridSpacing: CGFloat = .space16
}

/// The list body shown at every depth of Browse: root and every pushed subfolder
/// render this same view, scoped to their own `BrowseFeature` store. The list/grid
/// choice is a per-device display preference, not per-folder state, so it's stored
/// directly here rather than threaded through `BrowseFeature.State`.
struct BrowseContentView: View {
    @Bindable var store: StoreOf<BrowseFeature>
    @AppStorage("browseViewMode") private var viewModeRaw = BrowseViewMode.list.rawValue
    @State private var isSortSheetPresented = false
    /// The rename alert's in-progress text: kept as plain view state rather than routed
    /// through the store, since a `.alert` `TextField` bound via a TCA `.sending` binding
    /// didn't reliably propagate keystrokes back out. Seeded from `renameSheetItem` when
    /// the alert is presented; `renameConfirmed` is sent this value directly.
    @State private var renameDraft = ""

    private var viewMode: BrowseViewMode {
        BrowseViewMode(rawValue: viewModeRaw) ?? .list
    }

    var body: some View {
        Group {
            if viewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .tint(Color.accent)
        #if os(iOS)
        .searchable(
            text: $store.searchQuery.sending(\.searchQueryChanged),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        #else
        .searchable(
            text: $store.searchQuery.sending(\.searchQueryChanged),
            prompt: "Search"
        )
        #endif
        .searchScopes($store.searchScope.sending(\.searchScopeChanged)) {
            ForEach(BrowseFeature.SearchScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .refreshable {
            store.send(.refreshButtonTapped)
        }
        .overlay {
            overlayStateContent
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.directoryPath.isEmpty {
                BrowseBreadcrumbBar(directoryPath: store.directoryPath) { path, title in
                    store.send(.breadcrumbTapped(path: path, title: title))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSortSheetPresented = true
                } label: {
                    IconKit.arrowUpArrowDown
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModeRaw = (viewMode == .list ? BrowseViewMode.grid : .list).rawValue
                } label: {
                    viewMode == .list ? IconKit.squareGrid : IconKit.listBullet
                }
            }
        }
        .sheet(isPresented: $isSortSheetPresented) {
            BrowseSortSheet(
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
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
        .sheet(item: infoItemBinding) { item in
            FileInfoSheet(
                item: item,
                metadata: store.infoMetadata,
                isLoading: store.isLoadingInfoMetadata,
                errorMessage: store.infoErrorMessage,
                onDismiss: { store.send(.infoDismissed) }
            )
        }
        .task {
            store.send(.onAppear)
        }
    }

    private var infoItemBinding: Binding<FileItem?> {
        Binding(
            get: { store.infoItem },
            set: { if $0 == nil { store.send(.infoDismissed) } }
        )
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

    @ViewBuilder
    private func fileActionsContextMenu(for item: FileItem) -> some View {
        // Explicit `.tint`: this whole view is under `.tint(Color.accent)`, which would
        // otherwise cascade into the menu and color every icon/label gold instead of the
        // system's normal label color — only Delete should stand out, in red.
        Button {
            store.send(.infoTapped(item))
        } label: {
            Label("Get Info", systemImage: "info.circle")
        }
        .tint(.primaryDS)
        if store.access?.canWrite ?? false {
            Button {
                store.send(.renameTapped(item))
            } label: {
                Label("Rename", systemImage: "square.and.pencil")
            }
            .tint(.primaryDS)
        }
        // Only folders can be favorited — the server 400s on anything else.
        if item.isDirectory {
            Button {
                store.send(.favoriteToggleButtonTapped(item))
            } label: {
                if store.favoritePaths.contains(item.id) {
                    Label("Remove from Favorites", systemImage: "star.fill")
                } else {
                    Label("Add to Favorites", systemImage: "star")
                }
            }
            .tint(.primaryDS)
        }
        if store.access?.canDelete ?? false {
            Button(role: .destructive) {
                store.send(.deleteTapped(item))
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.negative)
        }
    }

    @ViewBuilder
    private var overlayStateContent: some View {
        if store.isLoading && store.items.isEmpty {
            ProgressView()
        } else if let errorMessage = store.errorMessage {
            EmptyStateView(icon: IconKit.exclamationmarkTriangle, message: errorMessage)
        } else if !store.isSearching && store.displayedItems.isEmpty {
            EmptyStateView(icon: IconKit.folder, message: "This folder is empty.")
        } else if store.isSearching && store.searchScope == .everywhere && store.isSearchingEverywhere {
            ProgressView()
        } else if store.isSearching, let results = store.displayedSearchResults, results.isEmpty {
            noResultsState
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
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: Constants.gridColumns, spacing: Constants.gridSpacing) {
                if store.isSearching {
                    ForEach(store.displayedSearchResults ?? []) { result in
                        Button {
                            store.send(.searchResultTapped(result))
                        } label: {
                            GridCellView(name: result.name, isDirectory: result.isDirectory, isFavorite: store.favoritePaths.contains(result.id))
                        }
                        .buttonStyle(.plain)
                        .disabled(!result.isDirectory)
                    }
                } else {
                    ForEach(store.displayedItems) { item in
                        Button {
                            store.send(.rowTapped(item))
                        } label: {
                            GridCellView(name: item.name, isDirectory: item.isDirectory, isFavorite: store.favoritePaths.contains(item.id))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            fileActionsContextMenu(for: item)
                        }
                    }
                }
            }
            .padding(Constants.gridSpacing)
        }
        .background(Color.backgroundPrimary)
    }

    @ViewBuilder
    private var folderItemRows: some View {
        ForEach(store.displayedItems) { item in
            Button {
                store.send(.rowTapped(item))
            } label: {
                FileRowView(item: item, isFavorite: store.favoritePaths.contains(item.id))
            }
            .buttonStyle(.plain)
            .contextMenu {
                fileActionsContextMenu(for: item)
            }
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing) {
                if store.access?.canDelete ?? false {
                    Button {
                        store.send(.deleteTapped(item))
                    } label: {
                        IconKit.trash
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
                        IconKit.squareAndPencil
                    }
                    .tint(.positive)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        ForEach(store.displayedSearchResults ?? []) { result in
            Button {
                store.send(.searchResultTapped(result))
            } label: {
                FileRowView(name: result.name, isDirectory: result.isDirectory, subtitle: result.matchLine, isFavorite: store.favoritePaths.contains(result.id))
            }
            .buttonStyle(.plain)
            .disabled(!result.isDirectory)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var noResultsState: some View {
        VStack(spacing: Constants.emptyStateSpacing) {
            IconKit.magnifyingGlass
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.emptyStateIconSize, height: Constants.emptyStateIconSize)
            Text("No matches for \u{201C}\(store.searchQuery)\u{201D}.")
                .type(.body1(.semibold), style: .secondary)
            if store.searchScope == .thisFolder {
                DSButton("Search everywhere",
                         icon: IconKit.magnifyingGlass,
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

