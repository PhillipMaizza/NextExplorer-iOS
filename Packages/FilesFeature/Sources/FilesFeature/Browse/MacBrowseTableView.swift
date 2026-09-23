#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    /// Generic views can't hold static stored properties, so the shared formatter lives here.
    @MainActor
    private enum TableFormat {
        static let byteFormatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter
        }()
    }

    private enum Metrics {
        static let iconSize: CGFloat = .iconSmall
        static let nameColumnMinWidth: CGFloat = 220
        static let dateColumnWidth: CGFloat = 170
        static let sizeColumnWidth: CGFloat = 90
        static let kindColumnWidth: CGFloat = 90
    }

    /// Browse's Mac only table mode: sortable columns backed by the store's own sort, double click
    /// to open, and the same file actions menu as the list and grid. Rows arrive already sorted
    /// by `BrowseFeature`, so a header click only forwards the new sort to the store.
    struct MacBrowseTableView<ContextMenu: View>: View {
        let items: IdentifiedArrayOf<FileItem>
        let sortOption: BrowseFeature.SortOption
        let sortDirection: BrowseFeature.SortDirection
        let onSortChanged: (BrowseFeature.SortOption, BrowseFeature.SortDirection) -> Void
        @Binding var selection: Set<FileItem.ID>
        let onOpen: (FileItem) -> Void
        let keyboardActions: BrowseKeyboardActions
        let serverURL: URL
        let canDropOnFolders: Bool
        let onDropOnFolder: ([FileItem.ID], FileItem) -> Void
        @ViewBuilder let contextMenu: (FileItem) -> ContextMenu

        @Dependency(\.filesClient) private var filesClient
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue

        var body: some View {
            Table(of: FileItem.self, selection: $selection, sortOrder: sortOrder) {
                TableColumn(L10n.Sort.name, value: \.name) { item in
                    HStack(spacing: .space8) {
                        icon(for: item)
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                    }
                }
                .width(min: Metrics.nameColumnMinWidth)
                TableColumn(L10n.Sort.dateModified, value: \.dateModified) { item in
                    Text(dateFormat.string(from: item.dateModified, includeTime: true))
                        .foregroundStyle(Color.secondaryDS)
                }
                .width(Metrics.dateColumnWidth)
                TableColumn(L10n.Sort.size, value: \.size) { item in
                    Text(item.isDirectory ? "" : TableFormat.byteFormatter.string(fromByteCount: item.size))
                        .foregroundStyle(Color.secondaryDS)
                        .monospacedDigit()
                }
                .width(Metrics.sizeColumnWidth)
                TableColumn(L10n.Sort.kind, value: \.kind) { item in
                    Text(item.isDirectory ? L10n.FileInfo.navigationTitleFolder : item.kind.uppercased())
                        .foregroundStyle(Color.secondaryDS)
                }
                .width(Metrics.kindColumnWidth)
            } rows: {
                ForEach(items) { item in
                    TableRow(item)
                        .draggable(DraggedServerItem(item: item, serverURL: serverURL, filesClient: filesClient))
                        .dropDestination(for: ServerItemReference.self) { references in
                            let ids = references.map(\.id).filter { $0 != item.id }
                            guard canDropOnFolders, item.isDirectory, !ids.isEmpty else { return }
                            onDropOnFolder(ids, item)
                        }
                }
            }
            .contextMenu(forSelectionType: FileItem.ID.self) { ids in
                if ids.count == 1, let item = item(for: ids.first) {
                    contextMenu(item)
                }
            } primaryAction: { ids in
                if ids.count == 1, let item = item(for: ids.first) {
                    onOpen(item)
                }
            }
            .scrollContentBackground(.hidden)
            // Finder conventions: Space previews, Return renames, Delete deletes; Edit menu
            // Cut/Copy/Paste/Select All and ⌘I reach the selection through the focused value.
            .onKeyPress(.space) {
                guard selection.count == 1, let item = item(for: selection.first) else { return .ignored }
                onOpen(item)
                return .handled
            }
            .onKeyPress(.return) {
                guard selection.count == 1 else { return .ignored }
                keyboardActions.rename()
                return .handled
            }
            .onDeleteCommand { keyboardActions.delete() }
            .focusedValue(\.browseKeyboardActions, keyboardActions)
        }

        private var dateFormat: DateDisplayFormat {
            DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
        }

        private func item(for id: FileItem.ID?) -> FileItem? {
            items.first { $0.id == id }
        }

        @ViewBuilder
        private func icon(for item: FileItem) -> some View {
            if item.isDirectory {
                IconKit.folderFill
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            } else {
                FileTypeIcon(kind: item.kind)
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            }
        }

        /// The store owns the sort; the table only renders it and reports header clicks.
        private var sortOrder: Binding<[KeyPathComparator<FileItem>]> {
            Binding(
                get: { [Self.comparator(for: sortOption, direction: sortDirection)] },
                set: { newValue in
                    guard let first = newValue.first else { return }
                    onSortChanged(Self.option(for: first), first.order == .forward ? .ascending : .descending)
                }
            )
        }

        private static func comparator(
            for option: BrowseFeature.SortOption,
            direction: BrowseFeature.SortDirection
        ) -> KeyPathComparator<FileItem> {
            let order: SortOrder = direction == .ascending ? .forward : .reverse
            return switch option {
            case .name: KeyPathComparator(\.name, order: order)
            case .dateModified: KeyPathComparator(\.dateModified, order: order)
            case .size: KeyPathComparator(\.size, order: order)
            case .kind: KeyPathComparator(\.kind, order: order)
            }
        }

        private static func option(for comparator: KeyPathComparator<FileItem>) -> BrowseFeature.SortOption {
            switch comparator.keyPath {
            case \FileItem.dateModified: .dateModified
            case \FileItem.size: .size
            case \FileItem.kind: .kind
            default: .name
            }
        }
    }

    /// What the Edit and File menus can do to the focused file table's selection.
    public struct BrowseKeyboardActions {
        public let cut: () -> Void
        public let copy: () -> Void
        public let paste: () -> Void
        public let delete: () -> Void
        public let rename: () -> Void
        public let selectAll: () -> Void
        public let getInfo: () -> Void
        public let canPaste: Bool
    }

    public extension FocusedValues {
        @Entry var browseKeyboardActions: BrowseKeyboardActions?
    }
#endif
