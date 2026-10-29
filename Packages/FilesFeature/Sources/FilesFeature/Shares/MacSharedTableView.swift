#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        /// Narrower than Browse's: this table has two more columns.
        static let nameColumnMinWidth: CGFloat = 180
        static let locationColumnMinWidth: CGFloat = 120
        static let audienceColumnMinWidth: CGFloat = 110
        static let accessColumnWidth: CGFloat = 100
        static let dateColumnMinWidth: CGFloat = 120
        static let dateColumnIdealWidth: CGFloat = 160
        static let deletingOpacity: Double = 0.4
    }

    /// One Shared segment as a Mac table, matching Browse's: sortable columns backed by the
    /// store's own sort, the link actions on right click, double click or Delete for a share you
    /// own. Expired links follow the active ones, their expiry in red. "With me" stays read
    /// only, as on iOS and the web.
    struct MacSharedTableView: View {
        let store: StoreOf<SharedFeature>
        let segment: SharedFeature.Segment
        let onToast: (DSToastMessage) -> Void

        @State private var selection: Set<Share.ID> = []
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        @FocusState private var isFocused: Bool

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

        private var shares: [Share] {
            if isLoading {
                return SharedSegmentList.placeholderShares
            }
            let partition = store.state.displayedSharesPartition(for: segment)
            return Array(partition.active) + Array(partition.expired)
        }

        var body: some View {
            table
                .scrollContentBackground(.hidden)
                // AppKit stripes the empty space below the rows at its default row height, which
                // never lines up with the taller rows here.
                .alternatingRowBackgrounds(.disabled)
                // The table's scroll view otherwise draws its header material up under the pinned title.
                .clipped()
                .allowsHitTesting(!isLoading)
                .focused($isFocused)
                .focusEffectDisabled()
                .onAppear { isFocused = true }
                .onDeleteCommand {
                    if let share = selectedOwnShare {
                        store.send(.deleteTapped(share))
                    }
                }
                .onChange(of: shares.map(\.id)) { _, ids in
                    selection.formIntersection(ids)
                }
                .syncRefreshFeedback(errorMessage: phase.errorMessage, signalsErrorHaptic: false) {
                    await store.send(.refreshRequested).finish()
                }
                .overlay {
                    ListStateOverlay(
                        phase: listPhase,
                        errorMessage: phase.errorMessage,
                        emptyIcon: IconKit.shareLink,
                        emptyMessage: store.state.emptyMessage(for: segment),
                        noResultsMessage: L10n.Shared.noSearchMatches(store.searchQuery),
                        pullOffset: 0,
                        onRetry: { store.send(.refreshRequested) }
                    )
                }
                .animation(DSMotion.contentReveal, value: listPhase)
        }

        private var table: some View {
            Table(of: Share.self, selection: $selection, sortOrder: sortOrder) {
                TableColumn(L10n.Sort.name, value: \.displayName) { share in
                    HStack(spacing: .space8) {
                        icon(for: share)
                        Text(share.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !isLoading, store.state.isExpired(share) {
                            ExpiredBadge()
                        }
                    }
                    .padding(.vertical, MacBrowseTableMetrics.rowVerticalPadding)
                    .modifier(PlaceholderCell(isActive: isLoading))
                    .opacity(opacity(for: share))
                }
                .width(min: Metrics.nameColumnMinWidth)
                if isByMe {
                    TableColumn(L10n.FileInfo.rowLocation) { share in
                        secondaryText(share.sourcePath ?? "", for: share)
                            .truncationMode(.head)
                    }
                    .width(min: Metrics.locationColumnMinWidth)
                    TableColumn(L10n.Shared.metaSharedWith) { share in
                        secondaryText(audienceText(for: share), for: share)
                    }
                    .width(min: Metrics.audienceColumnMinWidth)
                }
                if !isByMe {
                    TableColumn(L10n.Shared.metaSharedBy) { share in
                        secondaryText(store.state.sharedByLabel(for: share), for: share)
                    }
                    .width(min: Metrics.audienceColumnMinWidth)
                }
                TableColumn(L10n.Shared.metaAccess) { share in
                    secondaryText(share.accessMode.title, for: share)
                }
                .width(Metrics.accessColumnWidth)
                TableColumn(L10n.Shared.metaExpiration, value: \.expirySortDate) { share in
                    Text(expiryText(for: share))
                        .lineLimit(1)
                        .foregroundStyle(store.state.isExpired(share) ? Color.negative : Color.secondaryDS)
                        .modifier(PlaceholderCell(isActive: isLoading))
                        .opacity(opacity(for: share))
                }
                .width(min: Metrics.dateColumnMinWidth, ideal: Metrics.dateColumnIdealWidth)
                TableColumn(L10n.Sort.dateShared, value: \.createdAt) { share in
                    secondaryText(dateFormat.string(from: share.createdAt, includeTime: true), for: share)
                }
                .width(min: Metrics.dateColumnMinWidth, ideal: Metrics.dateColumnIdealWidth)
            } rows: {
                ForEach(shares) { share in
                    TableRow(share)
                }
            }
            .contextMenu(forSelectionType: Share.ID.self) { ids in
                if isByMe, ids.count == 1, let share = share(for: ids.first) {
                    menu(for: share)
                }
            } primaryAction: { ids in
                if isByMe, ids.count == 1, let share = share(for: ids.first) {
                    store.send(.editTapped(share))
                }
            }
        }

        @ViewBuilder
        private func menu(for share: Share) -> some View {
            Menu(L10n.Common.copy) {
                Button(L10n.Shared.actionShareLink) {
                    copy(share.shareLink(serverURL: store.serverURL), label: L10n.Shared.copiedShareLink)
                }
                Menu(share.isDirectory ? L10n.Shared.actionFolderLink : L10n.Shared.actionFileLink) {
                    ForEach(DirectLinkMode.allCases) { mode in
                        Button(mode.title) {
                            copy(
                                share.directLink(serverURL: store.serverURL, mode: mode),
                                label: share.isDirectory ? L10n.Shared.copiedFolderZip : L10n.Shared.copiedDirectFile
                            )
                        }
                    }
                }
            }
            Divider()
            Button(L10n.Common.edit) { store.send(.editTapped(share)) }
            Button(L10n.Common.delete, role: .destructive) { store.send(.deleteTapped(share)) }
        }

        private func secondaryText(_ text: String, for share: Share) -> some View {
            Text(text)
                .lineLimit(1)
                .foregroundStyle(Color.secondaryDS)
                .modifier(PlaceholderCell(isActive: isLoading))
                .opacity(opacity(for: share))
        }

        private func icon(for share: Share) -> some View {
            // Decorative: the name already says what the share is.
            Group {
                if share.isDirectory {
                    MacTableFolderIcon(image: IconKit.folderFill, tint: Color.accent)
                } else {
                    // A custom label often drops the extension; the shared file's own name keeps it.
                    FileTypeIcon(kind: ((share.sourceName ?? share.sourcePath ?? share.displayName) as NSString).pathExtension)
                        .frame(width: MacBrowseTableMetrics.iconSize, height: MacBrowseTableMetrics.iconSize)
                }
            }
            .accessibilityHidden(true)
        }

        private func audienceText(for share: Share) -> String {
            switch store.state.audience(for: share) {
            case .anyone:
                return L10n.Shared.anyoneWithLink
            case let .users(names, unnamed):
                let more = unnamed > 0 ? [L10n.Shared.moreRecipients(unnamed)] : []
                return (names + more).joined(separator: ", ")
            }
        }

        private func expiryText(for share: Share) -> String {
            guard let expiresAt = share.expiresAt else { return L10n.Common.never }
            return dateFormat.string(from: expiresAt, includeTime: true)
        }

        private func opacity(for share: Share) -> Double {
            store.deletingIDs.contains(share.id) ? Metrics.deletingOpacity : 1
        }

        private var dateFormat: DateDisplayFormat {
            DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
        }

        private var selectedOwnShare: Share? {
            guard isByMe, selection.count == 1 else { return nil }
            return share(for: selection.first)
        }

        private func share(for id: Share.ID?) -> Share? {
            shares.first { $0.id == id }
        }

        private func copy(_ string: String, label: String) {
            PlatformPasteboard.copy(string)
            onToast(.success(label))
        }

        /// The store owns the sort; the table only renders it and reports header clicks.
        private var sortOrder: Binding<[KeyPathComparator<Share>]> {
            Binding(
                get: { [Self.comparator(for: store.sortOption, direction: store.sortDirection)] },
                set: { newValue in
                    guard let first = newValue.first else { return }
                    store.send(.sortOptionChanged(Self.option(for: first)))
                    store.send(.sortDirectionChanged(first.order == .forward ? .ascending : .descending))
                }
            )
        }

        private static func comparator(
            for option: SharedFeature.SortOption,
            direction: BrowseFeature.SortDirection
        ) -> KeyPathComparator<Share> {
            let order: SortOrder = direction == .ascending ? .forward : .reverse
            return switch option {
            case .name: KeyPathComparator(\.displayName, order: order)
            case .expiration: KeyPathComparator(\.expirySortDate, order: order)
            case .dateShared: KeyPathComparator(\.createdAt, order: order)
            }
        }

        private static func option(for comparator: KeyPathComparator<Share>) -> SharedFeature.SortOption {
            switch comparator.keyPath {
            case \Share.expirySortDate: .expiration
            case \Share.createdAt: .dateShared
            default: .name
            }
        }
    }

    /// The red tag iOS shows on an expired link's header, beside the name.
    private struct ExpiredBadge: View {
        var body: some View {
            Text(L10n.Shared.badgeExpired.uppercased())
                .type(.caption(.semibold), style: .error)
                .padding(.horizontal, SharedLinkMetrics.badgeHorizontalPadding)
                .padding(.vertical, SharedLinkMetrics.badgeVerticalPadding)
                .background(RoundedRectangle(cornerRadius: .radiusXSmall).fill(Color.negative.opacity(0.15)))
                .fixedSize()
        }
    }

    /// Redacted and shimmering per cell while the segment's first page loads, as
    /// `MacBrowseTableSkeleton` does.
    private struct PlaceholderCell: ViewModifier {
        let isActive: Bool

        func body(content: Content) -> some View {
            if isActive {
                content
                    .redacted(reason: .placeholder)
                    .shimmering()
            } else {
                content
            }
        }
    }

    private extension Share {
        /// A link that never expires sorts after every dated one.
        var expirySortDate: Date {
            expiresAt ?? .distantFuture
        }
    }

    @MainActor
    private func sharedTablePreview(
        segment: SharedFeature.Segment = .byMe,
        _ mutate: (inout SharedFeature.State) -> Void
    ) -> some View {
        var state = SharedFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        )
        mutate(&state)
        let store = Store(initialState: state) { SharedFeature() } withDependencies: {
            $0.filesClient = .previewValue
        }
        return MacSharedTableView(store: store, segment: segment, onToast: { _ in })
            .backgroundGradient()
            .frame(width: 900, height: 400)
    }

    private let previewTableShares: [Share] = [
        .previewCard(isDirectory: true),
        .previewCard(target: .users, sourcePath: "Documents/Team/Roadmap"),
        .previewCard(expiresAt: Date().addingTimeInterval(-3600)),
    ]

    #Preview("Shared table — by me") {
        sharedTablePreview {
            $0.byMe = IdentifiedArray(uniqueElements: previewTableShares)
            $0.phases[.byMe] = .loaded
        }
    }

    #Preview("Shared table — with me") {
        sharedTablePreview(segment: .withMe) {
            $0.withMe = IdentifiedArray(uniqueElements: [.previewCard(sourcePath: nil)])
            $0.phases[.withMe] = .loaded
        }
    }

    #Preview("Shared table — loading") {
        sharedTablePreview { $0.phases[.byMe] = .loading }
    }

    #Preview("Shared table — empty") {
        sharedTablePreview { $0.phases[.byMe] = .loaded }
    }

    #Preview("Shared table — error") {
        sharedTablePreview { $0.phases[.byMe] = .failed(L10n.EmptyState.loadFailed) }
    }

    #Preview("Shared table — no search results") {
        sharedTablePreview {
            $0.byMe = IdentifiedArray(uniqueElements: previewTableShares)
            $0.phases[.byMe] = .loaded
            $0.searchQuery = "zzzznomatch"
        }
    }
#endif
