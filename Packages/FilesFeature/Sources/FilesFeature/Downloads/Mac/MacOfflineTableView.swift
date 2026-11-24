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
    struct MacOfflineTableView: View {
        let store: StoreOf<OfflineTabFeature>
        let offlineStore: StoreOf<OfflineManageFeature>
        let pinned: [OfflinePinnedRootUsage]
        let saved: [LocalDownload]
        var favorites: IdentifiedArrayOf<Favorite> = []
        let onPreview: (LocalDownload) -> Void

        /// The offline run's phase, kept here so the table updates per phase, not per progress tick.
        @State private var phase = OfflineDownloadProgress.Phase.idle
        @State private var selection: Set<MacOfflineTableRow.ID> = []
        @FocusState private var isFocused: Bool

        private var rows: [MacOfflineTableRow] {
            pinned.map(MacOfflineTableRow.pinned) + saved.map(MacOfflineTableRow.saved)
        }

        var body: some View {
            let rows = rows
            Table(rows, selection: $selection, sortOrder: sortOrder) {
                TableColumn(L10n.Sort.name, value: \.sortName) { row in
                    HStack(spacing: .space8) {
                        icon(for: row)
                        Text(row.sortName).lineLimit(1).truncationMode(.middle)
                        if row.pinned != nil {
                            MacTableFolderIcon(
                                image: IconKit.availableOffline,
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
                TableColumn(L10n.FileInfo.rowLocation) { row in
                    Text(location(of: row))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                }
                .width(min: Metrics.locationColumnMinWidth)
                TableColumn(L10n.Sort.size, value: \.sortSize) { row in
                    Text(FileSizeFormat.string(row.sortSize))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(MacBrowseTableMetrics.sizeColumnWidth)
            }
            .contextMenu(forSelectionType: MacOfflineTableRow.ID.self) { ids in
                menu(for: ids)
                    .labelStyle(.titleAndIcon)
            } primaryAction: { ids in
                if ids.count == 1, let row = row(for: ids.first, in: rows) {
                    open(row)
                }
            }
            .macBoardTable()
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
                Button(role: .destructive) { remove(ids) } label: {
                    Label { Text(L10n.Common.remove) } icon: { IconKit.delete }
                }
            } else if !selected.isEmpty, selected.allSatisfy({ $0.saved != nil }) {
                Button(role: .destructive) { remove(ids) } label: {
                    Label { Text(L10n.Common.delete) } icon: { IconKit.delete }
                }
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
            case let .pinned(usage): usage.parentPath
            case .saved: L10n.Offline.sectionSavedEarlier
            }
        }

        private func row(for id: MacOfflineTableRow.ID?, in rows: [MacOfflineTableRow]) -> MacOfflineTableRow? {
            rows.first { $0.id == id }
        }

        /// A pinned folder opens in place, a pinned file previews from its kept copy, a saved file previews.
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
