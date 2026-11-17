#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let locationColumnMinWidth: CGFloat = 180
        static let deletedByColumnWidth: CGFloat = 120
        static let removedColumnWidth: CGFloat = 130
        static let unavailableOpacity: Double = 0.5
    }

    /// The trash as the Mac sidebar's Trash section: a table like Browse's, with the item actions on
    /// right click, double click to look inside a folder or read a text file, and Empty Trash.
    struct MacTrashView: View {
        @Bindable var store: StoreOf<TrashFeature>
        @State private var selection: Set<TrashItem.ID> = []
        @Dependency(\.date) private var date
        @Dependency(\.calendar) private var calendar

        var body: some View {
            NavigationStack {
                content
                    .navigationTitle(L10n.Trash.title)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button(role: .destructive) { store.send(.emptyTrashTapped) } label: {
                                Label { Text(L10n.Trash.emptyTrash) } icon: { IconKit.delete }
                            }
                            .disabled(store.items.isEmpty || store.isBusy)
                        }
                    }
                    .toolbar { TrashRestoreCancelButton(store: store.scope(state: \.restore, action: \.restore)) }
                    .navigationDestination(item: $store.scope(state: \.folder, action: \.folder)) { folderStore in
                        TrashFolderView(store: folderStore)
                    }
            }
            .task { store.send(.task) }
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

        /// How long items stay, or that the trash is off, under the table as on iOS.
        private var footnote: String? {
            guard store.isEnabled else { return L10n.Trash.disabledNotice }
            return store.retentionDays.map { L10n.Trash.subtitle($0) }
        }

        private var content: some View {
            TrashPhaseContent(phase: store.phase, isEmpty: store.items.isEmpty, onRetry: { store.send(.retryTapped) }) {
                EmptyStateView(icon: IconKit.delete, message: L10n.Trash.emptyState)
            } loaded: {
                table
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let footnote {
                    Text(footnote)
                        .type(.body3(.regular), style: .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .space16)
                        .padding(.vertical, .space8)
                }
            }
        }

        private var table: some View {
            Table(store.displayedItems, selection: $selection, sortOrder: sortOrder) {
                TableColumn(L10n.Sort.name, value: \.name) { item in
                    HStack(spacing: .space8) {
                        icon(for: item)
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        if item.shareCount > 0 {
                            MacTableFolderIcon(
                                image: IconKit.shareLink,
                                tint: .accent,
                                size: MacBrowseTableMetrics.badgeSize
                            )
                            .accessibilityLabel(L10n.Trash.sharesBadge)
                        }
                    }
                    .padding(.vertical, MacBrowseTableMetrics.rowVerticalPadding)
                    .opacity(item.isAvailable ? 1 : Metrics.unavailableOpacity)
                }
                .width(min: MacBrowseTableMetrics.nameColumnMinWidth)
                TableColumn(L10n.Trash.columnOriginalLocation) { item in
                    Text(item.isAvailable ? TrashRowText.location(item) : L10n.Trash.unavailable)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(Color.secondaryDS)
                }
                .width(min: Metrics.locationColumnMinWidth)
                TableColumn(L10n.Trash.columnDeletedBy) { item in
                    Text(TrashRowText.deletedBy(item)).foregroundStyle(Color.secondaryDS)
                }
                .width(Metrics.deletedByColumnWidth)
                TableColumn(L10n.Trash.columnDeletedOn, value: \.sortDeletedAt) { item in
                    Text(TrashRowText.deletedOn(item) ?? "").foregroundStyle(Color.secondaryDS)
                }
                .width(MacBrowseTableMetrics.dateColumnWidth)
                TableColumn(L10n.Trash.columnRemoved) { item in
                    Text(TrashRowText.removal(item, now: date.now, calendar: calendar) ?? "")
                        .foregroundStyle(Color.secondaryDS)
                }
                .width(Metrics.removedColumnWidth)
                TableColumn(L10n.Sort.size, value: \.sortSize) { item in
                    Text(item.size.map(FileSizeFormat.string) ?? "")
                        .foregroundStyle(Color.secondaryDS)
                        .monospacedDigit()
                }
                .width(MacBrowseTableMetrics.sizeColumnWidth)
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
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .clipped()
            .disabled(store.isBusy)
            .onChange(of: store.items) { _, items in selection.formIntersection(items.ids) }
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
                    Label { Text(L10n.Trash.restore) } icon: { IconKit.restore }
                }
                Button { store.send(.restoreToTapped(picked)) } label: {
                    Label { Text(L10n.Trash.restoreTo) } icon: { IconKit.restoreTo }
                }
                Divider()
                Button(role: .destructive) { store.send(.deletePermanentlyTapped(picked)) } label: {
                    Label { Text(L10n.Trash.deletePermanently) } icon: { IconKit.delete }
                }
            }
        }

        private func items(_ ids: Set<TrashItem.ID>) -> [TrashItem] {
            store.items.filter { ids.contains($0.id) }
        }

        private func icon(for item: TrashItem) -> some View {
            Group {
                if item.isDirectory {
                    MacTableFolderIcon(image: IconKit.folderFill, tint: Color.accent)
                } else {
                    FileTypeIcon(kind: TrashRowText.kind(item.name, isDirectory: false))
                        .frame(width: MacBrowseTableMetrics.iconSize, height: MacBrowseTableMetrics.iconSize)
                }
            }
            .accessibilityHidden(true)
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
