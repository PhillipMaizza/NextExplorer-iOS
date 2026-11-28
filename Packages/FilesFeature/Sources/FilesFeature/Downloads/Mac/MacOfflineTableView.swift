#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let locationColumnMinWidth: CGFloat = 200
    }

    /// One row of the Offline table: an item kept offline, or a file saved by an earlier version.
    enum MacOfflineTableRow: Identifiable, Equatable {
        case pinned(OfflinePinnedRootUsage)
        case saved(LocalDownload)

        /// Prefixed, so a pinned path never collides with a saved file's path.
        var id: String {
            switch self {
            case let .pinned(usage): "pinned:\(usage.id)"
            case let .saved(download): "saved:\(download.id)"
            }
        }

        var pinned: OfflinePinnedRootUsage? {
            if case let .pinned(usage) = self {
                usage
            } else {
                nil
            }
        }

        var saved: LocalDownload? {
            if case let .saved(download) = self {
                download
            } else {
                nil
            }
        }

        /// What the Name and Size headers sort by; the rows arrive sorted by the store.
        var sortName: String {
            switch self {
            case let .pinned(usage): usage.displayName
            case let .saved(download): download.fileName
            }
        }

        var sortSize: Int64 {
            switch self {
            case let .pinned(usage): usage.sizeBytes
            case let .saved(download): download.size
            }
        }
    }

    /// The Offline tab as a Mac table, matching Favorites and Browse: name, location and size
    /// columns, double click to open a folder or preview a saved file, the row actions on right
    /// click and Delete to remove. The selection is the table's own; there is no select mode on the Mac.
    private enum Column {
        case location
        case size
    }

    struct MacOfflineTableView: View {
        let store: StoreOf<OfflineTabFeature>
        let offlineStore: StoreOf<OfflineManageFeature>
        let pinned: [OfflinePinnedRootUsage]
        let saved: [LocalDownload]
        var favorites: IdentifiedArrayOf<Favorite> = []
        let onPreview: (LocalDownload) -> Void

        /// The offline run's phase, kept here so the table updates per phase, not per progress tick.
        @State private var phase = OfflineDownloadProgress.Phase.idle
        @Environment(\.macOfflineSelection) private var sharedSelection
        @State private var ownSelection: Set<MacOfflineTableRow.ID> = []

        private var selectionBinding: Binding<Set<MacOfflineTableRow.ID>> {
            sharedSelection ?? $ownSelection
        }

        private var selection: Set<MacOfflineTableRow.ID> {
            get { selectionBinding.wrappedValue }
            nonmutating set { selectionBinding.wrappedValue = newValue }
        }

        @FocusState private var isFocused: Bool
        @State private var isPeeking = false
        @State private var width: CGFloat = .zero
        @Dependency(\.offlineFileStore) private var offlineFileStore

        private var columns: MacTableColumnFit<Column> {
            MacTableColumnFit(
                width: width,
                nameWidth: MacBrowseTableMetrics.nameColumnMinWidth,
                spacing: MacTableMetrics.columnSpacing,
                byPriority: [
                    (.size, MacBrowseTableMetrics.sizeColumnWidth),
                    (.location, Metrics.locationColumnMinWidth),
                ]
            )
        }

        private var rows: [MacOfflineTableRow] {
            pinned.map(MacOfflineTableRow.pinned) + saved.map(MacOfflineTableRow.saved)
        }

        var body: some View {
            let rows = rows
            Table(rows, selection: selectionBinding, sortOrder: sortOrder) {
                TableColumn(L10n.Sort.name, value: \.sortName) { row in
                    HStack(spacing: .space8) {
                        icon(for: row)
                        MacFileNameText(name: row.sortName, isDirectory: row.pinned?.root.isDirectory == true)
                        if row.pinned != nil {
                            MacTableFolderIcon(
                                image: MenuIcon.keepOffline.image,
                                tint: Color.accent,
                                size: MacBrowseTableMetrics.badgeSize
                            )
                            .accessibilityLabel(L10n.Offline.badgeAvailable)
                            if let title = OfflineSyncState(phase: phase).title {
                                Text(title).type(.body3(.regular)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .macBoardTableCell()
                }
                .width(min: MacBrowseTableMetrics.nameColumnMinWidth)
                if columns.shows(.location) {
                    TableColumn(L10n.FileInfo.rowLocation) { row in
                        Text(location(of: row))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: Metrics.locationColumnMinWidth)
                }
                if columns.shows(.size) {
                    TableColumn(L10n.Sort.size, value: \.sortSize) { row in
                        Text(FileSizeFormat.string(row.sortSize))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(MacBrowseTableMetrics.sizeColumnWidth)
                }
            }
            .contextMenu(forSelectionType: MacOfflineTableRow.ID.self) { ids in
                menu(for: ids)
                    .labelStyle(.titleAndIcon)
            } primaryAction: { ids in
                open(ids, in: rows)
            }
            .macOpenShortcut(isEnabled: isFocused) { open(selection, in: rows) }
            .macBoardTable(showsHeaders: !rows.isEmpty)
            .macBrowseTableWidth($width)
            // The table's scroll view otherwise draws its header material up under the pinned title.
            .clipped()
            .focused($isFocused)
            .focusEffectDisabled()
            .focusedWhenOnTop($isFocused)
            .onKeyPress(.return) {
                guard selection.count == 1, let row = row(for: selection.first, in: rows) else { return .ignored }
                open(row)
                return .handled
            }
            .onDeleteCommand { remove(selection) }
            .modifier(peek(rows))
            .onOfflinePhaseChange(isInitial: true) { phase = $0 }
            .onChange(of: rows.map(\.id)) { _, ids in
                selection.formIntersection(ids)
            }
        }

        @ViewBuilder
        private func menu(for ids: Set<MacOfflineTableRow.ID>) -> some View {
            let selected = ids.compactMap { row(for: $0, in: rows) }
            if selected.count == 1, let download = selected.first?.saved {
                DownloadRowContextMenu(store: store, download: download)
            } else if !selected.isEmpty, selected.allSatisfy({ $0.pinned != nil }) {
                if selected.count == 1, let root = selected.first?.pinned?.root, !root.isDirectory {
                    Section {
                        MacLocalFileMenuItems(
                            resolve: offlineFileStore.keptCopy(of: OfflineDownloadsFeature.fileItem(from: root))
                        )
                    }
                }
                Button(role: .destructive) { remove(ids) } label: {
                    Label { Text(L10n.Common.remove) } icon: { MenuIcon.delete.image }
                }
                .tint(.negative)
            } else if !selected.isEmpty, selected.allSatisfy({ $0.saved != nil }) {
                Button(role: .destructive) { remove(ids) } label: {
                    Label { Text(L10n.Common.delete) } icon: { MenuIcon.delete.image }
                }
                .tint(.negative)
            }
        }

        private func icon(for row: MacOfflineTableRow) -> some View {
            // Decorative: the name column already says what the row is.
            Group {
                switch row {
                case let .pinned(usage) where usage.root.isDirectory:
                    if let favorite = favorites.first(where: { $0.path == usage.root.path }) {
                        MacFavoriteTile(favorite: favorite)
                    } else {
                        MacItemTile(kind: usage.kind, isDirectory: true, size: MacBrowseTableMetrics.tileSize)
                    }
                case let .pinned(usage):
                    MacItemTile(kind: usage.kind, isDirectory: false, size: MacBrowseTableMetrics.tileSize)
                case let .saved(download):
                    MacItemTile(name: download.fileName, isDirectory: false)
                }
            }
            .accessibilityHidden(true)
        }

        /// The store owns the sort, shared with the phone's sort sheet; a header click only reports it.
        /// Pinned items stay above saved files, each sorted. Date Added has no column, so the table
        /// then shows no sort arrow.
        private var sortOrder: Binding<[KeyPathComparator<MacOfflineTableRow>]> {
            Binding(
                get: {
                    let order: SortOrder = store.sortDirection == .ascending ? .forward : .reverse
                    return switch store.sortOption {
                    case .name: [KeyPathComparator(\.sortName, order: order)]
                    case .size: [KeyPathComparator(\.sortSize, order: order)]
                    case .dateAdded: []
                    }
                },
                set: { newValue in
                    guard let first = newValue.first else { return }
                    let option: OfflineTabFeature.SortOption = first.keyPath == \MacOfflineTableRow.sortSize
                        ? .size
                        : .name
                    store.send(.sortOptionChanged(option))
                    store.send(.sortDirectionChanged(first.order == .forward ? .ascending : .descending))
                }
            )
        }

        private func location(of row: MacOfflineTableRow) -> String {
            switch row {
            case let .pinned(usage): MacInspectorLocation.trail(parent: usage.parentPath)
            case .saved: L10n.Offline.sectionSavedEarlier
            }
        }

        private func open(_ ids: Set<MacOfflineTableRow.ID>, in rows: [MacOfflineTableRow]) {
            if ids.count == 1, let row = row(for: ids.first, in: rows) {
                open(row)
            }
        }

        private func row(for id: MacOfflineTableRow.ID?, in rows: [MacOfflineTableRow]) -> MacOfflineTableRow? {
            rows.first { $0.id == id }
        }

        /// A pinned folder opens in place, a pinned file previews from its kept copy, a saved file previews.
        private func peek(_ rows: [MacOfflineTableRow]) -> MacItemPeek<EmptyView> {
            let pinnedRows = rows.filter { $0.pinned != nil }
            return MacItemPeek(
                item: selection.count == 1 ? peekItem(for: selection.first, in: rows) : nil,
                items: pinnedRows.compactMap { peekItem(for: $0.id, in: rows) },
                isPeeking: $isPeeking,
                serverURL: store.serverURL,
                shouldShowThumbnails: store.preferences.shouldShowThumbnails,
                showsHiddenFiles: store.preferences.shouldShowHiddenFiles,
                isSavedOffline: { _ in true },
                size: { item in pinned.first { $0.root.path == item.id }?.sizeBytes },
                onSelect: { item in
                    guard let row = pinnedRows.first(where: { $0.pinned?.root.path == item.id }) else { return }
                    selection = [row.id]
                },
                onOpen: { item in
                    guard let row = pinnedRows.first(where: { $0.pinned?.root.path == item.id }) else { return }
                    open(row)
                },
                showsMore: false,
                isListFocused: $isFocused,
                more: { _ in EmptyView() }
            )
        }

        private func peekItem(for id: MacOfflineTableRow.ID?, in rows: [MacOfflineTableRow]) -> FileItem? {
            guard let usage = row(for: id, in: rows)?.pinned else { return nil }
            return OfflineDownloadsFeature.fileItem(from: usage.root)
        }

        private func open(_ row: MacOfflineTableRow) {
            switch row {
            case let .pinned(usage):
                store.send(.pinnedItemTapped(usage.root))
            case let .saved(download):
                onPreview(download)
            }
        }

        /// Pins go through the removal confirmation; one saved file through its own delete
        /// confirmation and several through the bulk one. A selection mixing both does nothing, as
        /// each kind asks its own question and only one can be open at a time.
        private func remove(_ ids: Set<MacOfflineTableRow.ID>) {
            let selected = ids.compactMap { row(for: $0, in: rows) }
            let paths = selected.compactMap { $0.pinned?.root.path }
            let downloads = selected.compactMap(\.saved)
            guard paths.isEmpty || downloads.isEmpty else { return }
            if !paths.isEmpty {
                offlineStore.send(.removeSelectionTapped(paths: paths), animation: DSMotion.listDiff)
            } else if downloads.count == 1, let download = downloads.first {
                store.send(.deleteTapped(download))
            } else if downloads.count > 1 {
                store.send(.deselectAllTapped)
                for download in downloads {
                    store.send(.itemSelectionToggled(download.id))
                }
                store.send(.bulkDeleteTapped)
            }
        }
    }

    private let previewPinned = [
        OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Documents", isDirectory: true), sizeBytes: 45_000_000),
        OfflinePinnedRootUsage(
            root: OfflinePinnedRoot(path: "Photos/trip.jpg", isDirectory: false),
            sizeBytes: 3_200_000
        ),
    ]

    private let previewSaved = [
        LocalDownload(
            url: URL(fileURLWithPath: "/tmp/report.pdf"),
            fileName: "report.pdf",
            size: 1_200_000,
            modifiedDate: Date()
        ),
    ]

    #Preview("Offline table") {
        MacOfflineTableView(
            store: Store(initialState: OfflineTabFeature.State()) { OfflineTabFeature() },
            offlineStore: Store(initialState: OfflineManageFeature.State()) { OfflineManageFeature() },
            pinned: previewPinned,
            saved: previewSaved,
            onPreview: { _ in }
        )
        .previewCanvas(.table)
    }

    #Preview("Pinned only") {
        MacOfflineTableView(
            store: Store(initialState: OfflineTabFeature.State()) { OfflineTabFeature() },
            offlineStore: Store(initialState: OfflineManageFeature.State()) { OfflineManageFeature() },
            pinned: previewPinned,
            saved: [],
            onPreview: { _ in }
        )
        .previewCanvas(.table)
    }
#endif
