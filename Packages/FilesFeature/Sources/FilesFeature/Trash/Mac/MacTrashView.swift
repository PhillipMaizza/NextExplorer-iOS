#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        // The detail columns give way before the sidebar does: fixed widths summed past the window
        // and squeezed the sidebar.
        static let nameColumnMinWidth: CGFloat = 160
        static let locationColumnMinWidth: CGFloat = 110
        static let deletedByColumnWidth: CGFloat = 100
        static let dateColumnWidth: CGFloat = 116
        static let removedColumnWidth: CGFloat = 130
        static let sizeColumnWidth: CGFloat = 70
        static let unavailableOpacity: Double = .opacityHalf
    }

    private enum TrashColumn {
        case location, deletedBy, deletedOn, removed, size

        static func fit(width: CGFloat) -> MacTableColumnFit<Self> {
            MacTableColumnFit(
                width: width,
                nameWidth: Metrics.nameColumnMinWidth,
                spacing: MacTableMetrics.columnSpacing,
                byPriority: [
                    (.deletedOn, Metrics.dateColumnWidth),
                    (.location, Metrics.locationColumnMinWidth),
                    (.removed, Metrics.removedColumnWidth),
                    (.size, Metrics.sizeColumnWidth),
                    (.deletedBy, Metrics.deletedByColumnWidth),
                ]
            )
        }
    }

    /// The trash as the Mac sidebar's Trash section: a table like Browse's, with the item actions on
    /// right click, double click to look inside a folder or read a text file, and Empty Trash.
    struct MacTrashView: View {
        @Bindable var store: StoreOf<TrashFeature>
        @State private var selection: Set<TrashItem.ID> = []
        @FocusState private var isFocused: Bool
        @State private var width = CGFloat.infinity
        @Dependency(\.date) private var date
        @Dependency(\.calendar) private var calendar

        var body: some View {
            NavigationStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .macToolbarRefresh(onRefresh: { await store.send(.refreshPulled).finish() }, onFinished: {})
                    .safeAreaInset(edge: .top, spacing: .zero) {
                        MacPaneHeader(
                            title: L10n.Trash.title,
                            subtitle: footnote.isEmpty || isGuideShown ? nil : footnote,
                            inset: MacPaneInset.sectionHeader,
                            bottom: MacPaneInset.listGap
                        ) {
                            Button(role: .destructive) { store.send(.emptyTrashTapped) } label: {
                                Label { Text(L10n.Trash.emptyTrash) } icon: { MenuIcon.delete.image }
                            }
                            .buttonStyle(.macDS(.secondary))
                            .disabled(store.items.isEmpty || store.isBusy)
                        }
                    }
                    .navigationDestination(item: $store.scope(state: \.folder, action: \.folder)) { folderStore in
                        TrashFolderView(store: folderStore)
                    }
            }
            .instantPushOnMac(depth: store.folder == nil ? 0 : 1)
            .task { store.send(.task) }
            .focusedSceneValue(\.macSearchText, $store.searchQuery.sending(\.searchQueryChanged))
            .modifier(TrashRestorePrompts(
                store: store.scope(state: \.restore, action: \.restore),
                screenNotice: store.notice
            ))
            .dsAlert(isPresented: confirmationBinding) {
                TrashConfirmation.alert(
                    store.confirmation,
                    isRunning: store.confirmPhase.isRunning,
                    onConfirm: { store.send(.confirmationConfirmed) },
                    onDismiss: { store.send(.confirmationDismissed) }
                )
            }
            .sheet(isPresented: textBinding) {
                TrashTextSheet(state: store.text) { store.send(.textDismissed) }
                    .frame(minWidth: MacSheetMetrics.textMinWidth, minHeight: MacSheetMetrics.textMinHeight)
            }
        }

        /// How long items stay, or that the trash is off, under the window title.
        private var footnote: String {
            guard store.isEnabled else { return L10n.Trash.disabledNotice }
            return store.retentionDays.map { L10n.Trash.subtitle($0) } ?? ""
        }

        private var isGuideShown: Bool {
            store.isEnabled && store.phase == .loaded && store.items.isEmpty
        }

        @ViewBuilder
        private var emptyGuide: some View {
            if store.isEnabled {
                Color.clear.macEmptyGuide(.trash(retentionDays: store.retentionDays))
            } else {
                EmptyStateView(icon: MenuIcon.delete.image, message: L10n.Trash.emptyState)
            }
        }

        private var content: some View {
            TrashPhaseContent(
                phase: store.phase,
                isEmpty: store.items.isEmpty,
                searchMiss: store.searchMiss,
                onRetry: { store.send(.retryTapped) }
            ) {
                emptyGuide
            } loaded: {
                table
            }
        }

        private var table: some View {
            let columns = TrashColumn.fit(width: width)
            return Table(store.displayedItems, selection: $selection, sortOrder: sortOrder) {
                TableColumn(L10n.Sort.name, value: \.name) { item in
                    HStack(spacing: .space8) {
                        icon(for: item)
                        MacFileNameText(name: item.name, isDirectory: item.isDirectory)
                        if item.shareCount > 0 {
                            MacTableFolderIcon(
                                image: MenuIcon.shareLink.image,
                                tint: .accent,
                                size: MacBrowseTableMetrics.badgeSize
                            )
                            .accessibilityLabel(L10n.Trash.sharesBadge)
                        }
                    }
                    .macBoardTableCell()
                    .opacity(item.isAvailable ? 1 : Metrics.unavailableOpacity)
                }
                .width(min: Metrics.nameColumnMinWidth)
                if columns.shows(.location) {
                    TableColumn(L10n.Trash.columnOriginalLocation) { item in
                        Text(item.isAvailable ? PathTrail.text(TrashRowText.location(item)) : L10n.Trash.unavailable)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: Metrics.locationColumnMinWidth)
                }
                if columns.shows(.deletedBy) {
                    TableColumn(L10n.Trash.columnDeletedBy) { item in
                        Text(TrashRowText.deletedBy(item)).foregroundStyle(.secondary)
                    }
                    .width(Metrics.deletedByColumnWidth)
                }
                if columns.shows(.deletedOn) {
                    TableColumn(L10n.Trash.columnDeletedOn, value: \.sortDeletedAt) { item in
                        Text(TrashRowText.deletedOn(item) ?? "").foregroundStyle(.secondary)
                    }
                    .width(Metrics.dateColumnWidth)
                }
                if columns.shows(.removed) {
                    TableColumn(L10n.Trash.columnRemoved) { item in
                        Text(TrashRowText.removal(item, now: date.now, calendar: calendar) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: Metrics.removedColumnWidth)
                }
                if columns.shows(.size) {
                    TableColumn(L10n.Sort.size, value: \.sortSize) { item in
                        Text(item.isDirectory ? L10n.Browse.noValue : item.size.map(FileSizeFormat.string) ?? "")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(Metrics.sizeColumnWidth)
                }
            }
            .contextMenu(forSelectionType: TrashItem.ID.self) { ids in
                menu(for: ids)
                    .labelStyle(.titleAndIcon)
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first, let item = store.items[id: id] {
                    store.send(.itemTapped(item))
                }
            }
            .onDeleteCommand { store.send(.deletePermanentlyTapped(items(selection))) }
            .macBoardTable()
            .macBrowseTableWidth($width)
            .backgroundGradient()
            .clipped()
            .focused($isFocused)
            .focusEffectDisabled()
            .focusedWhenOnTop($isFocused)
            .disabled(store.isBusy)
            .onChange(of: store.displayedItems.map(\.id)) { _, ids in selection.formIntersection(ids) }
        }

        /// The store owns the sort; the table renders it and reports header clicks.
        private var sortOrder: Binding<[KeyPathComparator<TrashItem>]> {
            Binding(
                get: {
                    let order: SortOrder = store.sortDirection == .ascending ? .forward : .reverse
                    return switch store.sortOption {
                    case .name: [KeyPathComparator(\.name, order: order)]
                    case .size: [KeyPathComparator(\.sortSize, order: order)]
                    case .deletedOn: [KeyPathComparator(\.sortDeletedAt, order: order)]
                    }
                },
                set: { newValue in
                    guard let first = newValue.first else { return }
                    let option: TrashSortOption = switch first.keyPath {
                    case \TrashItem.sortSize: .size
                    case \TrashItem.sortDeletedAt: .deletedOn
                    default: .name
                    }
                    store.send(.sortOptionChanged(option))
                    store.send(.sortDirectionChanged(first.order == .forward ? .ascending : .descending))
                }
            )
        }

        @ViewBuilder
        private func menu(for ids: Set<TrashItem.ID>) -> some View {
            let picked = items(ids)
            if picked.count == 1, let item = picked.first {
                TrashItemMenu(item: item, store: store)
            } else if !picked.isEmpty {
                Button { store.send(.restoreTapped(picked)) } label: {
                    Label { Text(L10n.Trash.restore) } icon: { MenuIcon.restore.image }
                }
                Button { store.send(.restoreToTapped(picked)) } label: {
                    Label { Text(L10n.Trash.restoreTo) } icon: { MenuIcon.restoreTo.image }
                }
                Divider()
                RemovableMenuButton(title: L10n.Trash.deletePermanently, icon: MenuIcon.delete.image, isRemoval: true) {
                    store.send(.deletePermanentlyTapped(picked))
                }
            }
        }

        private func items(_ ids: Set<TrashItem.ID>) -> [TrashItem] {
            store.displayedItems.filter { ids.contains($0.id) }
        }

        private func icon(for item: TrashItem) -> some View {
            MacItemTile(name: item.name, isDirectory: item.isDirectory)
        }

        private var confirmationBinding: Binding<Bool> {
            Binding(get: { store.confirmPhase != .idle }, set: { _ in })
        }

        private var textBinding: Binding<Bool> {
            Binding(get: { store.text.isPresented }, set: {
                if !$0 {
                    store.send(.textDismissed)
                }
            })
        }
    }

    private enum MacSheetMetrics {
        static let textMinWidth: CGFloat = 560
        static let textMinHeight: CGFloat = 420
    }

    #Preview("Trash") {
        MacTrashView(store: TrashPreviewData.trash())
            .frame(width: 900, height: 400)
    }

    #Preview("Trash, dark") {
        MacTrashView(store: TrashPreviewData.trash())
            .frame(width: 900, height: 400)
            .preferredColorScheme(.dark)
    }

    #Preview("Empty") {
        MacTrashView(store: TrashPreviewData.trash { $0.items = [] })
            .macEmptyGuideOverlay()
            .frame(width: 900, height: 400)
    }

    #Preview("Switched off") {
        MacTrashView(store: TrashPreviewData.trash { $0.isEnabled = false })
            .frame(width: 900, height: 400)
    }

    #Preview("Failed") {
        MacTrashView(store: TrashPreviewData.trash {
            $0.items = []
            $0.phase = .failed(L10n.Trash.loadFailed)
        })
        .frame(width: 900, height: 400)
    }
#endif
