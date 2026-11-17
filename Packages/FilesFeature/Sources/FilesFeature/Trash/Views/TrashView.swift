import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    /// An item whose volume is gone reads as out of reach.
    static let unavailableOpacity: Double = 0.5
}

/// The trash on iPhone and iPad, pushed from the Browse root's Trash row: the Browse rows, grid,
/// selection and sort, with the retention note under the list.
struct TrashView: View {
    @Bindable var store: StoreOf<TrashFeature>
    @AppStorage(AppStorageKeys.browseViewMode) private var viewModeRaw = FileListViewMode.list.rawValue
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue
    @State private var isSortSheetPresented = false
    @Dependency(\.date) private var date
    @Dependency(\.calendar) private var calendar

    private var isGridView: Bool {
        viewModeRaw == FileListViewMode.grid.rawValue
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundGradient()
            .safeAreaInset(edge: .top, spacing: 0) {
                PinnedTitleSearchHeader(
                    title: L10n.Trash.title,
                    selectionTitle: store.isSelecting ? L10n.Common.selectedCount(store.selectedIDs.count) : nil,
                    searchText: .constant(""),
                    showsSearchField: false
                )
            }
            .navigationHistoryTitle(L10n.Trash.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                TrashToolbar(
                    store: store,
                    isGridView: isGridView,
                    onSort: { isSortSheetPresented = true },
                    onToggleViewMode: toggleViewMode
                )
            }
            // Below the toolbar, so its Cancel can hide the circles before select mode ends.
            .selectModeChrome(isSelecting: store.isSelecting)
            .task { store.send(.task) }
            .modifier(TrashRestorePrompts(
                store: store.scope(state: \.restore, action: \.restore),
                screenNotice: store.notice
            ))
            .dsAlert(isPresented: confirmationBinding) { confirmationAlert }
            .dsSheet(isPresented: $isSortSheetPresented) { sortSheet }
            .sheet(isPresented: textBinding) {
                TrashTextSheet(state: store.text) { store.send(.textDismissed) }
            }
            .navigationDestination(item: $store.scope(state: \.folder, action: \.folder)) { folderStore in
                TrashFolderView(store: folderStore)
            }
    }

    private var content: some View {
        TrashPhaseContent(phase: store.phase, isEmpty: store.items.isEmpty, onRetry: { store.send(.retryTapped) }) {
            VStack(spacing: .space24) {
                EmptyStateView(icon: IconKit.delete, message: L10n.Trash.emptyState)
                footer
            }
            .padding(.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } loaded: {
            Group {
                if isGridView {
                    grid
                } else {
                    list
                }
            }
            .dragToSelect(
                isEnabled: store.isSelecting,
                selection: store.selectedIDs,
                order: { store.displayedItems.map(\.id) },
                onChange: { store.send(.selectionSwept($0)) }
            )
            .refreshable { await store.send(.refreshPulled).finish() }
        }
    }

    private var list: some View {
        let items = store.displayedItems
        let firstID = items.first?.id
        let lastID = items.last?.id
        return DSGroupedList {
            Section {
                ForEach(items) { item in
                    row(item, isFirst: item.id == firstID, isLast: item.id == lastID)
                }
            } footer: {
                footer
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .animation(DSMotion.listDiff, value: items)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: FileGridMetrics.columns, spacing: FileGridMetrics.spacing) {
                ForEach(store.displayedItems) { item in
                    cell(item)
                }
            }
            .padding(FileGridMetrics.spacing)
            .animation(DSMotion.listDiff, value: store.displayedItems)
            footer
                .padding(.horizontal, FileGridMetrics.spacing)
                .padding(.bottom, FileGridMetrics.spacing)
        }
    }

    /// How long items stay, or that the trash is off, under the list as Browse notes its own.
    @ViewBuilder
    private var footer: some View {
        if !store.isEnabled {
            DSInfoCard(L10n.Trash.disabledNotice)
        } else if let days = store.retentionDays {
            DSInfoCard(L10n.Trash.subtitle(days))
        }
    }

    private func row(_ item: TrashItem, isFirst: Bool, isLast: Bool) -> some View {
        SelectableListRow(
            selectionID: item.id,
            isSelecting: store.isSelecting,
            isSelected: store.selectedIDs.contains(item.id),
            isFirst: isFirst,
            isLast: isLast,
            onTap: { store.send(.itemTapped(item)) }
        ) {
            FileRowView(
                name: item.name,
                isDirectory: item.isDirectory,
                subtitle: TrashRowText.subtitle(item, now: date.now, calendar: calendar),
                kind: TrashRowText.kind(item.name, isDirectory: item.isDirectory),
                subtitleLineLimit: nil
            )
            .opacity(item.isAvailable ? 1 : Constants.unavailableOpacity)
        } trailingSwipe: {
            BrowseQuickActionButtons(actions: BrowseQuickAction.trashActions(for: item, store: store), style: .swipe)
        } contextMenu: {
            if !store.isSelecting {
                TrashItemMenu(item: item, store: store)
            }
        }
        .accessibilityActions {
            BrowseQuickActionButtons(
                actions: BrowseQuickAction.trashActions(for: item, store: store),
                style: .accessibility
            )
        }
    }

    private func cell(_ item: TrashItem) -> some View {
        SelectableGridCell(
            selectionID: item.id,
            isSelecting: store.isSelecting,
            isSelected: store.selectedIDs.contains(item.id),
            onTap: { store.send(.itemTapped(item)) }
        ) {
            GridCellView(
                name: item.name,
                isDirectory: item.isDirectory,
                kind: TrashRowText.kind(item.name, isDirectory: item.isDirectory),
                iconSize: (ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium).iconSize
            )
            .opacity(item.isAvailable ? 1 : Constants.unavailableOpacity)
        } contextMenu: {
            if !store.isSelecting {
                TrashItemMenu(item: item, store: store)
            }
        }
        .accessibilityActions {
            BrowseQuickActionButtons(
                actions: BrowseQuickAction.trashActions(for: item, store: store),
                style: .accessibility
            )
        }
    }

    private var sortSheet: some View {
        SortSheet(
            options: TrashSortOption.allCases,
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

    private func toggleViewMode() {
        withAnimation(DSMotion.contentReveal) {
            viewModeRaw = (isGridView ? FileListViewMode.list : .grid).rawValue
        }
    }

    private var textBinding: Binding<Bool> {
        Binding(get: { store.text.isPresented }, set: {
            if !$0 {
                store.send(.textDismissed)
            }
        })
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { store.confirmPhase != .idle }, set: { _ in })
    }

    private var confirmationAlert: DSAlertSheet {
        TrashConfirmation.alert(
            store.confirmation,
            isRunning: store.confirmPhase.isRunning,
            onConfirm: { store.send(.confirmationConfirmed) },
            onDismiss: { store.send(.confirmationDismissed) }
        )
    }
}

#Preview("Loaded") {
    NavigationStack { TrashView(store: TrashPreviewData.trash()) }
}

#Preview("Loaded, dark, large type") {
    NavigationStack { TrashView(store: TrashPreviewData.trash()) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Selecting") {
    NavigationStack {
        TrashView(store: TrashPreviewData.trash {
            $0.isSelecting = true
            $0.selectedIDs = ["t1"]
        })
    }
}

#Preview("Grid") {
    let defaults = UserDefaults(suiteName: "TrashGridPreview") ?? .standard
    defaults.set(FileListViewMode.grid.rawValue, forKey: AppStorageKeys.browseViewMode)
    return NavigationStack { TrashView(store: TrashPreviewData.trash()) }
        .defaultAppStorage(defaults)
}

#Preview("Switched off with leftovers") {
    NavigationStack { TrashView(store: TrashPreviewData.trash { $0.isEnabled = false }) }
}

#Preview("Empty") {
    NavigationStack { TrashView(store: TrashPreviewData.trash { $0.items = [] }) }
}

#Preview("Loading") {
    NavigationStack {
        TrashView(store: TrashPreviewData.trash {
            $0.items = []
            $0.phase = .loading
        })
    }
}

#Preview("Failed") {
    NavigationStack {
        TrashView(store: TrashPreviewData.trash {
            $0.items = []
            $0.phase = .failed(L10n.Trash.loadFailed)
        })
    }
}

#Preview("Empty Trash confirmation") {
    NavigationStack {
        TrashView(store: TrashPreviewData.trash {
            $0.confirmation = .empty
            $0.confirmPhase = .confirming
        })
    }
}
