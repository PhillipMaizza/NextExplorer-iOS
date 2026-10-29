#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import QuickLook
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

    /// Column layout shared with `MacBrowseTableSkeleton`, so loading and loaded line up.
    enum MacBrowseTableMetrics {
        static let iconSize: CGFloat = .iconMedium
        /// Extra room above and below each row's content, for rows taller than AppKit's default.
        static let rowVerticalPadding: CGFloat = .space4
        static let badgeSize: CGFloat = .iconXSmall
        /// Finder's look for rows staged by Cut.
        static let cutRowOpacity: Double = 0.5
        static let nameColumnMinWidth: CGFloat = 220
        static let dateColumnWidth: CGFloat = 170
        static let sizeColumnWidth: CGFloat = 90
        static let kindColumnWidth: CGFloat = 90
    }

    /// Browse's Mac only table mode: sortable columns backed by the store's own sort, double click
    /// to open, and the same file actions menu as the list and grid. Rows arrive already sorted
    /// by `BrowseFeature`, so a header click only forwards the new sort to the store. Right click
    /// hands `contextMenu` the clicked rows, empty for the table's empty space.
    struct MacBrowseTableView<ContextMenu: View>: View {
        let items: IdentifiedArrayOf<FileItem>
        let sortOption: BrowseFeature.SortOption
        let sortDirection: BrowseFeature.SortDirection
        let onSortChanged: (BrowseFeature.SortOption, BrowseFeature.SortDirection) -> Void
        @Binding var selection: Set<FileItem.ID>
        /// Rows staged by Cut, drawn dimmed until pasted or cleared.
        let cutItemIDs: Set<FileItem.ID>
        /// Items saved for offline use, badged like the iOS rows.
        let offlineItemIDs: Set<FileItem.ID>
        let onOpen: (FileItem) -> Void
        let keyboardActions: BrowseKeyboardActions
        let serverURL: URL
        let canDropOnFolders: Bool
        let onDropOnFolder: ([FileItem.ID], FileItem) -> Void
        @ViewBuilder let contextMenu: (Set<FileItem.ID>) -> ContextMenu
        /// The row being renamed in place, Finder style, instead of through a sheet.
        var renamingItemID: FileItem.ID?
        var onRenameCommit: (String) -> Void = { _ in }
        var onRenameCancel: () -> Void = {}
        /// The account's private folder, pinned as the first row on the root when the server has
        /// personal folders on. Its id is the `personal` path space, which is never a volume.
        var personalSpace: FileItem?
        var onOpenPersonalSpace: () -> Void = {}

        @Dependency(\.filesClient) private var filesClient
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        /// The table takes focus when a folder opens, so Cut, Copy and Paste reach it at once.
        @FocusState private var isFocused: Bool
        /// The local copy Quick Look is showing, fetched through the preview cache.
        @State private var quickLookURL: URL?
        @State private var quickLookTask: Task<Void, Never>?

        var body: some View {
            Table(of: FileItem.self, selection: $selection, sortOrder: sortOrder) {
                TableColumn(L10n.Sort.name, value: \.name) { item in
                    HStack(spacing: .space8) {
                        if isPersonalSpace(item) {
                            MacTableFolderIcon(image: IconKit.person, tint: Color.accent)
                        } else {
                            icon(for: item)
                        }
                        if item.id == renamingItemID {
                            InlineRenameField(originalName: item.name, onCommit: onRenameCommit, onCancel: onRenameCancel)
                        } else {
                            Text(isPersonalSpace(item) ? L10n.Browse.myFiles : item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if offlineItemIDs.contains(item.id) {
                            MacTableFolderIcon(image: IconKit.download, tint: Color.accent, size: MacBrowseTableMetrics.badgeSize)
                                .accessibilityLabel(L10n.Offline.badgeAvailable)
                        }
                    }
                    .padding(.vertical, MacBrowseTableMetrics.rowVerticalPadding)
                    .opacity(opacity(for: item))
                }
                .width(min: MacBrowseTableMetrics.nameColumnMinWidth)
                TableColumn(L10n.Sort.dateModified, value: \.dateModified) { item in
                    Text(isPersonalSpace(item) ? "" : dateFormat.string(from: item.dateModified, includeTime: true))
                        .foregroundStyle(Color.secondaryDS)
                        .opacity(opacity(for: item))
                }
                .width(MacBrowseTableMetrics.dateColumnWidth)
                TableColumn(L10n.Sort.size, value: \.size) { item in
                    Text(item.isDirectory ? "" : TableFormat.byteFormatter.string(fromByteCount: item.size))
                        .foregroundStyle(Color.secondaryDS)
                        .monospacedDigit()
                        .opacity(opacity(for: item))
                }
                .width(MacBrowseTableMetrics.sizeColumnWidth)
                TableColumn(L10n.Sort.kind, value: \.kind) { item in
                    Text(item.isDirectory ? L10n.FileInfo.navigationTitleFolder : item.kind.uppercased())
                        .foregroundStyle(Color.secondaryDS)
                        .opacity(opacity(for: item))
                }
                .width(MacBrowseTableMetrics.kindColumnWidth)
            } rows: {
                if let personalSpace {
                    TableRow(personalSpace)
                }
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
                // My Files has no file actions of its own.
                let fileIDs = ids.filter { $0 != personalSpace?.id }
                if fileIDs.count == ids.count || !fileIDs.isEmpty {
                    contextMenu(fileIDs)
                }
            } primaryAction: { ids in
                if ids.count == 1, ids.first == personalSpace?.id {
                    onOpenPersonalSpace()
                } else if ids.count == 1, let item = item(for: ids.first) {
                    onOpen(item)
                }
            }
            .scrollContentBackground(.hidden)
            // AppKit stripes the empty space below the rows at its default row height, which
            // never lines up with the taller rows here.
            .alternatingRowBackgrounds(.disabled)
            .backgroundGradient()
            // The table's scroll view otherwise draws its header material up under the pinned title.
            .clipped()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear { isFocused = true }
            // Finder conventions: Space toggles Quick Look on a file (and Get Info on a folder, which
            // a double click opens), Return renames, Delete deletes; Edit menu Cut/Copy/Paste/Select
            // All and ⌘I reach the selection through the focused value.
            .onKeyPress(.space) {
                guard selection.count == 1, let item = item(for: selection.first) else { return .ignored }
                if item.isDirectory {
                    keyboardActions.getInfo()
                } else if quickLookURL != nil {
                    closeQuickLook()
                } else {
                    quickLook(item)
                }
                return .handled
            }
            .quickLookPreview($quickLookURL)
            // Like Finder, an open Quick Look follows the selection.
            .onChange(of: selection) { _, newSelection in
                guard quickLookURL != nil else { return }
                if newSelection.count == 1, let item = item(for: newSelection.first), !item.isDirectory {
                    quickLook(item)
                } else {
                    closeQuickLook()
                }
            }
            .onKeyPress(.return) {
                guard selection.count == 1 else { return .ignored }
                keyboardActions.rename()
                return .handled
            }
            .onDeleteCommand { keyboardActions.delete() }
            .focusedValue(\.browseKeyboardActions, keyboardActions)
        }

        private func quickLook(_ item: FileItem) {
            quickLookTask?.cancel()
            quickLookTask = Task {
                guard let url = try? await filesClient.previewFile(serverURL, item), !Task.isCancelled else { return }
                quickLookURL = url
            }
        }

        private func closeQuickLook() {
            quickLookTask?.cancel()
            quickLookURL = nil
        }

        private func opacity(for item: FileItem) -> Double {
            cutItemIDs.contains(item.id) ? MacBrowseTableMetrics.cutRowOpacity : 1
        }

        private var dateFormat: DateDisplayFormat {
            DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
        }

        private func isPersonalSpace(_ item: FileItem) -> Bool {
            item.id == personalSpace?.id
        }

        private func item(for id: FileItem.ID?) -> FileItem? {
            items.first { $0.id == id }
        }

        private func icon(for item: FileItem) -> some View {
            // Decorative: the name and kind columns already say what the row is.
            Group {
                if item.isDirectory {
                    MacTableFolderIcon(image: IconKit.folderFill, tint: Color.accent)
                } else {
                    FileTypeIcon(kind: item.kind)
                        .frame(width: MacBrowseTableMetrics.iconSize, height: MacBrowseTableMetrics.iconSize)
                }
            }
            .accessibilityHidden(true)
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

    /// The name cell while renaming: Return or clicking away commits, Esc cancels. An unchanged
    /// or invalid name cancels instead of asking the server.
    private struct InlineRenameField: View {
        let originalName: String
        let onCommit: (String) -> Void
        let onCancel: () -> Void

        @State private var name: String
        @State private var isFinished = false
        @FocusState private var isFocused: Bool

        init(originalName: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.originalName = originalName
            self.onCommit = onCommit
            self.onCancel = onCancel
            _name = State(initialValue: originalName)
        }

        var body: some View {
            TextField(L10n.Browse.renameNamePlaceholder, text: $name)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { isFocused = true }
                .onSubmit { finish(commit: true) }
                .onExitCommand { finish(commit: false) }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        finish(commit: true)
                    }
                }
        }

        private func finish(commit: Bool) {
            guard !isFinished else { return }
            isFinished = true
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if commit, trimmed != originalName, FileNameValidation.isAcceptable(trimmed: trimmed) {
                onCommit(trimmed)
            } else {
                onCancel()
            }
        }
    }

    /// A tinted symbol sized for a table row's leading icon.
    struct MacTableFolderIcon: View {
        let image: Image
        let tint: Color
        var isFilled = true
        var size: CGFloat = MacBrowseTableMetrics.iconSize

        var body: some View {
            image
                .resizable()
                .scaledToFit()
                .symbolVariant(isFilled ? .fill : .none)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

    /// What the Edit and File menus can do to the focused file table's selection.
    public struct BrowseKeyboardActions {
        public let cut: () -> Void
        public let copy: () -> Void
        public let duplicate: () -> Void
        public let undo: () -> Void
        /// Whether a file operation is waiting to be undone; otherwise ⌘Z edits text as usual.
        public let canUndo: Bool
        public let paste: () -> Void
        public let delete: () -> Void
        public let rename: () -> Void
        public let selectAll: () -> Void
        public let getInfo: () -> Void
        public let canPaste: Bool
    }

    /// The visible Browse screen's sort, for the View menu's Sort By.
    public struct BrowseViewOptions {
        public let sortOption: BrowseFeature.SortOption
        public let sortDirection: BrowseFeature.SortDirection
        public let setSortOption: (BrowseFeature.SortOption) -> Void
        public let setSortDirection: (BrowseFeature.SortDirection) -> Void
    }

    public extension BrowseFeature.SortOption {
        var menuTitle: String {
            title
        }
    }

    public extension BrowseFeature.SortDirection {
        var menuTitle: String {
            title
        }
    }

    public extension FocusedValues {
        @Entry var browseKeyboardActions: BrowseKeyboardActions?
        @Entry var browseViewOptions: BrowseViewOptions?
    }
#endif
