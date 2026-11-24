#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let audienceColumnWidth: CGFloat = .size96
        static let sharerColumnWidth: CGFloat = 180
        static let dateColumnWidth: CGFloat = 120
        static let downloadsColumnWidth: CGFloat = .size96
    }

    struct MacSharedTableColumns: Equatable {
        enum Column {
            case audience
            case sharer
            case expires
            case lastOpened
            case downloads
            case received
        }

        private let shown: Set<Column>

        init(width: CGFloat, isByMe: Bool) {
            let byPriority: [(Column, CGFloat)] = isByMe
                ? [
                    (.expires, Metrics.dateColumnWidth),
                    (.audience, Metrics.audienceColumnWidth),
                    (.lastOpened, Metrics.dateColumnWidth),
                    (.downloads, Metrics.downloadsColumnWidth),
                ]
                : [
                    (.sharer, Metrics.sharerColumnWidth),
                    (.expires, Metrics.dateColumnWidth),
                    (.received, Metrics.dateColumnWidth),
                ]
            var used = MacBrowseTableMetrics.nameColumnMinWidth
            var shown: Set<Column> = []
            for (column, columnWidth) in byPriority {
                used += MacTableMetrics.columnSpacing + columnWidth
                guard used <= width else { break }
                shown.insert(column)
            }
            self.shown = shown
        }

        func shows(_ column: Column) -> Bool {
            shown.contains(column)
        }
    }

    /// One Shared segment as a Mac outline table grouped by item: an item with several shares opens
    /// to a row per share. Every column sorts, items and their shares alike. Right click and Delete
    /// act on one share you own; With me stays read only, as on iOS and the web.
    struct MacSharedTable: View {
        let store: StoreOf<SharedFeature>
        let segment: SharedFeature.Segment
        @Binding var selection: Set<MacSharedRow.ID>
        let onToast: (DSToastMessage) -> Void

        /// Sorted here by the columns: By me by name, With me newest received first.
        @State private var sortOrder: [KeyPathComparator<MacSharedRow>]
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        @FocusState private var isFocused: Bool
        @State private var width: CGFloat = .zero

        init(
            store: StoreOf<SharedFeature>,
            segment: SharedFeature.Segment,
            selection: Binding<Set<MacSharedRow.ID>>,
            onToast: @escaping (DSToastMessage) -> Void
        ) {
            self.store = store
            self.segment = segment
            _selection = selection
            self.onToast = onToast
            _sortOrder = State(initialValue: segment == .byMe
                ? [KeyPathComparator(\.name)]
                : [KeyPathComparator(\.createdAt, order: .reverse)])
        }

        private var isByMe: Bool {
            segment == .byMe
        }

        private var phase: DataPhase {
            store.state.phase(for: segment)
        }

        private var listPhase: ListPhase {
            .derive(
                hasError: phase.errorMessage != nil,
                hasLoaded: phase.hasLoaded,
                isEmpty: store.state.isEmpty(for: segment),
                hasNoResults: store.state.isSearchWithoutResults(for: segment)
            )
        }

        private var isLoading: Bool {
            listPhase == .loading
        }

        private var dateFormat: DateDisplayFormat {
            DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
        }

        var body: some View {
            let rows = (isLoading ? SharedSegmentList.placeholderItems : store.state.items(for: segment))
                .map { item in
                    var row = MacSharedRow(
                        item: item,
                        expiringShare: store.state.nearestExpiringShare(in: item),
                        sharer: isByMe ? "" : store.state.sharedByLabel(for: item.shares[0])
                    )
                    row.children?.sort(using: sortOrder)
                    return row
                }
                .sorted(using: sortOrder)
            table(rows)
                .macBoardTable()
                .macBrowseTableWidth($width)
                // The table's scroll view otherwise draws its header material up under the pinned title.
                .clipped()
                .allowsHitTesting(!isLoading)
                // The placeholder rows carry made up names; VoiceOver skips them.
                .accessibilityHidden(isLoading)
                .focused($isFocused)
                .focusEffectDisabled()
                .onAppear { isFocused = true }
                .onDeleteCommand {
                    if let share = ownShare(for: selection, in: rows) {
                        store.send(.deleteTapped(share))
                    }
                }
                .onChange(of: Self.allIDs(of: rows)) { _, ids in
                    selection.formIntersection(ids)
                }
                .syncRefreshFeedback(errorMessage: phase.errorMessage, shouldSignalErrorHaptic: false) {
                    await store.send(.refreshRequested).finish()
                }
                .overlay {
                    ListStateOverlay(
                        phase: listPhase,
                        errorMessage: phase.errorMessage,
                        emptyIcon: IconKit.shareLink,
                        emptyMessage: store.state.emptyMessage(for: segment),
                        noResultsMessage: store.state.noResultsMessage(for: segment),
                        pullOffset: 0,
                        onRetry: { store.send(.refreshRequested) }
                    )
                }
                .animation(DSMotion.contentReveal, value: listPhase)
        }

        private func table(_ rows: [MacSharedRow]) -> some View {
            Group {
                if rows.contains(where: { $0.children != nil }) {
                    Table(rows, children: \.children, selection: $selection, sortOrder: $sortOrder) { columns }
                } else {
                    Table(rows, selection: $selection, sortOrder: $sortOrder) { columns }
                }
            }
            .contextMenu(forSelectionType: MacSharedRow.ID.self) { ids in
                if let share = ownShare(for: ids, in: rows) {
                    MacSharedRowMenu(share: share, store: store, onToast: onToast)
                        .labelStyle(.titleAndIcon)
                }
            }
            // Escape deselects, which closes the inspector.
            .onExitCommand {
                if store.editPopover != nil {
                    store.send(.editPopoverDismissed)
                } else {
                    selection = []
                }
            }
        }

        @TableColumnBuilder<MacSharedRow, KeyPathComparator<MacSharedRow>>
        private var columns: some TableColumnContent<MacSharedRow, KeyPathComparator<MacSharedRow>> {
            let shown = MacSharedTableColumns(width: width, isByMe: isByMe)
            TableColumn(L10n.Sort.name, value: \.name) { row in
                MacSharedNameCell(
                    row: row,
                    serverURL: isByMe ? store.serverURL : nil,
                    sizedFile: store.shareFiles[row.item.shares[0].id],
                    onNeedsSize: { store.send(.shareFileNeeded(row.item.shares[0])) },
                    isExpired: !isLoading && isExpired(row)
                )
                .macBoardTableCell()
                .modifier(MacSharedPlaceholderCell(isActive: isLoading))
                .opacity(opacity(for: row))
            }
            .width(min: MacBrowseTableMetrics.nameColumnCompactWidth)
            if shown.shows(.audience) {
                TableColumn(L10n.Shared.metaSharedWith, value: \.recipientCount) { row in
                    SharedAudienceBadgeRow(badges: badges(for: row), ringColor: Color.backgroundPrimary)
                        .modifier(MacSharedPlaceholderCell(isActive: isLoading))
                        .opacity(opacity(for: row))
                }
                .width(Metrics.audienceColumnWidth)
            }
            if shown.shows(.sharer) {
                TableColumn(L10n.Shared.metaSharedBy, value: \.sharer) { row in
                    MacSharedSharerCell(name: row.sharer)
                        .modifier(MacSharedPlaceholderCell(isActive: isLoading))
                }
                .width(Metrics.sharerColumnWidth)
            }
            if shown.shows(.expires) {
                TableColumn(L10n.Shared.metaExpires, value: \.expirySortDate) { row in
                    let share = row.expiringShare
                    MacSharedExpiryCell(
                        expiresAt: share?.expiresAt,
                        notice: isLoading ? nil : share.flatMap(store.state.expiryNotice(for:)),
                        dateFormat: dateFormat
                    )
                    .modifier(MacSharedPlaceholderCell(isActive: isLoading))
                    .opacity(opacity(for: row))
                }
                .width(Metrics.dateColumnWidth)
            }
            if shown.shows(.lastOpened) {
                TableColumn(L10n.Shared.metaLastOpened, value: \.lastOpenedSortDate) { row in
                    secondaryText(
                        SharedShareFacts.lastOpened(row.lastOpenedAt),
                        for: row
                    )
                }
                .width(Metrics.dateColumnWidth)
            }
            if shown.shows(.downloads) {
                TableColumn(L10n.Shared.metaDownloads, value: \.downloadCount) { row in
                    secondaryText(row.downloadCount.formatted(), for: row)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(Metrics.downloadsColumnWidth)
            }
            if shown.shows(.received) {
                TableColumn(L10n.Shared.metaReceived, value: \.createdAt) { row in
                    secondaryText(dateFormat.string(from: row.createdAt), for: row)
                }
                .width(Metrics.dateColumnWidth)
            }
        }

        private func secondaryText(_ text: String, for row: MacSharedRow) -> some View {
            Text(text)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .modifier(MacSharedPlaceholderCell(isActive: isLoading))
                .opacity(opacity(for: row))
        }

        private func isExpired(_ row: MacSharedRow) -> Bool {
            row.child.map(store.state.isExpired) ?? row.item.isExpired
        }

        private func badges(for row: MacSharedRow) -> [SharedFeature.ShareBadge] {
            guard let child = row.child else { return row.item.badges }
            return row.item.badges.filter { $0.id == child.id }
        }

        private func opacity(for row: MacSharedRow) -> Double {
            let ids = row.child.map { [$0.id] } ?? row.item.shares.map(\.id)
            return ids.allSatisfy(store.deletingIDs.contains) ? SharedRowMetrics.deletingOpacity : 1
        }

        /// Nil while that share's delete is in flight, so it cannot be deleted or edited twice.
        private func ownShare(for ids: Set<MacSharedRow.ID>, in rows: [MacSharedRow]) -> Share? {
            guard isByMe, ids.count == 1, let id = ids.first,
                  let share = Self.row(id, in: rows)?.share, !store.deletingIDs.contains(share.id)
            else { return nil }
            return share
        }

        private static func row(_ id: MacSharedRow.ID, in rows: [MacSharedRow]) -> MacSharedRow? {
            for row in rows {
                if row.id == id {
                    return row
                }
                if let child = row.children?.first(where: { $0.id == id }) {
                    return child
                }
            }
            return nil
        }

        private static func allIDs(of rows: [MacSharedRow]) -> [MacSharedRow.ID] {
            rows.flatMap { [$0.id] + ($0.children?.map(\.id) ?? []) }
        }
    }

    @MainActor
    private func tablePreview(
        _ segment: SharedFeature.Segment,
        mutate: (inout SharedFeature.State) -> Void = { _ in }
    ) -> some View {
        macSharedPreview(segment, mutate: mutate) {
            MacSharedTable(store: $0, segment: segment, selection: .constant([]), onToast: { _ in })
        }
        .previewCanvas(.table)
    }

    #Preview("Table: by me") {
        tablePreview(.byMe)
    }

    #Preview("Table: by me, dark") {
        tablePreview(.byMe)
            .preferredColorScheme(.dark)
    }

    #Preview("Table: with me") {
        tablePreview(.withMe)
    }

    #Preview("Table: loading") {
        tablePreview(.byMe) { $0.phases[.byMe] = .loading }
    }

    #Preview("Table: empty") {
        tablePreview(.byMe) { $0.byMe = [] }
    }

    #Preview("Table: error") {
        tablePreview(.byMe) {
            $0.byMe = []
            $0.phases[.byMe] = .failed(L10n.EmptyState.loadFailed)
        }
    }

    #Preview("Table: no search results") {
        tablePreview(.byMe) { $0.searchQuery = "zzzznomatch" }
    }
#endif
