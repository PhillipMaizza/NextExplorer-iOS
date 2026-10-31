#if os(macOS)
    import AppKit
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

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
        /// Favorited items, starred like the iOS rows.
        var favoriteItemIDs: Set<FileItem.ID> = []
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
        /// Space on a file Quick Look can't show: the reason, for the screen's toast.
        var onQuickLookUnavailable: (String) -> Void = { _ in }

        @Dependency(\.filesClient) private var filesClient
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        /// The table takes focus when a folder opens, so Cut, Copy and Paste reach it at once.
        @FocusState private var isFocused: Bool
        /// The system Quick Look panel, showing a local copy fetched through the preview cache.
        @State private var quickLookPanel = MacQuickLookPanel()
        @State private var isQuickLooking = false
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
                            MacInlineRenameField(originalName: item.name, onCommit: onRenameCommit, onCancel: onRenameCancel)
                        } else {
                            Text(isPersonalSpace(item) ? L10n.Browse.myFiles : item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                // A cut row is only dimmed on screen; VoiceOver says so in words.
                                // On the name alone, never the rename field, whose value is its text.
                                .accessibilityValue(cutItemIDs.contains(item.id) ? L10n.Browse.actionCut : "")
                        }
                        if offlineItemIDs.contains(item.id) {
                            MacTableFolderIcon(image: IconKit.download, tint: Color.accent, size: MacBrowseTableMetrics.badgeSize)
                                .accessibilityLabel(L10n.Offline.badgeAvailable)
                        }
                        if favoriteItemIDs.contains(item.id) {
                            MacTableFolderIcon(image: IconKit.starFill, tint: Color.accent, size: MacBrowseTableMetrics.badgeSize)
                                .accessibilityLabel(L10n.Favorites.accessibilityBadge)
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
                    Text(item.isDirectory ? "" : FileSizeFormat.string(item.size))
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
                    // A Mac menu shows only the title of a Label unless asked for the icon.
                    contextMenu(fileIDs)
                        .labelStyle(.titleAndIcon)
                }
            } primaryAction: { ids in
                // AppKit runs the primary action for Return as well as a double click; Finder
                // renames on Return, so a key press renames and only a click opens.
                if NSApp.currentEvent?.type == .keyDown {
                    if ids.count == 1, ids.first != personalSpace?.id {
                        keyboardActions.rename()
                    }
                } else if ids.count == 1, ids.first == personalSpace?.id {
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
            // The panel is the app's shared one; leaving the folder must not leave it showing a
            // file from here, or a download running for it.
            .onDisappear(perform: closeQuickLook)
            // Finder conventions: Space toggles Quick Look on a file (and Get Info on a folder, which
            // a double click opens), Return renames, Delete deletes; Edit menu Cut/Copy/Paste/Select
            // All and ⌘I reach the selection through the focused value.
            .onKeyPress(.space) {
                guard selection.count == 1, let item = item(for: selection.first) else { return .ignored }
                if item.isDirectory {
                    keyboardActions.getInfo()
                } else if quickLookPanel.isVisible {
                    closeQuickLook()
                } else {
                    quickLook(item)
                }
                return .handled
            }
            // Like Finder, an open Quick Look follows the selection.
            .onChange(of: selection) { _, newSelection in
                guard isQuickLooking, quickLookPanel.isVisible else { return }
                if newSelection.count == 1, let item = item(for: newSelection.first), !item.isDirectory {
                    quickLook(item)
                } else {
                    closeQuickLook()
                }
            }
            // Finder's ⌘↓ opens the selection. A key equivalent, since the table takes arrow
            // keys before `onKeyPress` sees them; live only while the table has focus.
            .background {
                Button(L10n.Browse.open) {
                    if selection.count == 1 {
                        keyboardActions.open()
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!isFocused)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onDeleteCommand { keyboardActions.delete() }
            .focusedValue(\.browseKeyboardActions, keyboardActions)
        }

        private func quickLook(_ item: FileItem) {
            if let reason = MacQuickLookPolicy.refusal(for: item, isSavedOffline: offlineItemIDs.contains(item.id)) {
                closeQuickLook()
                onQuickLookUnavailable(reason)
                return
            }
            isQuickLooking = true
            quickLookTask?.cancel()
            quickLookTask = Task {
                // The preview endpoint only serves the types the web app previews; anything else
                // comes down whole, so Quick Look can show it too.
                let url: URL? = if let preview = try? await filesClient.previewFile(serverURL, item) {
                    preview
                } else {
                    try? await filesClient.downloadRawFile(serverURL, item)
                }
                guard let url, !Task.isCancelled, isQuickLooking else { return }
                quickLookPanel.show(url, onMove: moveQuickLookSelection) {
                    isQuickLooking = false
                    quickLookTask?.cancel()
                }
            }
        }

        private func closeQuickLook() {
            isQuickLooking = false
            quickLookTask?.cancel()
            quickLookTask = nil
            quickLookPanel.close()
        }

        /// Up and Down in the Quick Look panel: select the previous or next file in the table,
        /// skipping folders, and the panel follows the selection.
        private func moveQuickLookSelection(by offset: Int) {
            let files = items.filter { !$0.isDirectory }
            guard let current = selection.first,
                  let index = files.firstIndex(where: { $0.id == current }),
                  files.indices.contains(index + offset) else { return }
            selection = [files[index + offset].id]
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
            id.flatMap { items[id: $0] }
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

    #Preview("Table") {
        @Previewable @State var selection: Set<FileItem.ID> = []
        let items: IdentifiedArrayOf<FileItem> = [
            FileItem(name: "Projects", path: "", dateModified: Date(), size: 0, kind: "directory"),
            FileItem(name: "report.pdf", path: "", dateModified: Date().addingTimeInterval(-86_400), size: 182_000, kind: "pdf"),
            FileItem(name: "beach.jpg", path: "", dateModified: Date().addingTimeInterval(-86_400 * 9), size: 2_400_000, kind: "jpg"),
        ]
        MacBrowseTableView(
            items: items,
            sortOption: .name,
            sortDirection: .ascending,
            onSortChanged: { _, _ in },
            selection: $selection,
            cutItemIDs: [],
            offlineItemIDs: [items[1].id],
            favoriteItemIDs: [items[0].id, items[1].id],
            onOpen: { _ in },
            keyboardActions: .preview,
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            canDropOnFolders: true,
            onDropOnFolder: { _, _ in },
            contextMenu: { _ in EmptyView() }
        )
        .previewCanvas(.table)
    }
#endif
