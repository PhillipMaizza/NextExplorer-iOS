#if os(macOS)
    import AppKit
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    /// Browse's Mac only table: sortable columns on the store's own sort, double click to open, and the
    /// file actions menu of the list and grid. Rows arrive sorted by `BrowseFeature`, so a header click
    /// only forwards the new sort. Right click hands `contextMenu` the clicked rows, none for empty space.
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
        var folderSizes: [FileItem.ID: Int64] = [:]
        var shouldShowThumbnails = false
        let onOpen: (FileItem) -> Void
        let keyboardActions: BrowseKeyboardActions
        let serverURL: URL
        let scope: String
        let canDropOnFolders: Bool
        var canExportFiles = true
        let onDropOnFolder: ([FileItem.ID], FileItem) -> Void
        /// Rows from another Browse window dropped on a folder row, which this table doesn't list.
        var onDropForeignItemsOnFolder: ([FileItem], FileItem) -> Void = { _, _ in }
        /// Finder files dropped on a folder row upload into it; `false` where uploads aren't allowed.
        var canUploadToFolders = false
        var onFilesDroppedOnFolder: ([URL], FileItem) -> Void = { _, _ in }
        @ViewBuilder let contextMenu: (Set<FileItem.ID>) -> ContextMenu
        /// The row being renamed in place, Finder style, instead of through a sheet.
        var renamingItemID: FileItem.ID?
        var onRenameCommit: (String) -> Void = { _ in }
        var onRenameCancel: () -> Void = {}
        /// The account's private folder, pinned as the first row on the root when the server has
        /// personal folders on. Its id is the `personal` path space, which is never a volume.
        var personalSpace: FileItem?
        var onOpenPersonalSpace: () -> Void = {}
        var isPeeking = false
        var onPeek: () -> Void = {}
        /// A row to scroll into view, such as the file a search opened this folder for.
        var scrollTargetID: FileItem.ID?
        var onScrollTargetShown: () -> Void = {}

        @Dependency(\.filesClient) private var filesClient
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        /// The table takes focus when a folder opens, so Cut, Copy and Paste reach it at once.
        @FocusState private var isFocused: Bool
        @State private var width = CGFloat.infinity

        var body: some View {
            let columns = MacBrowseTableColumns(width: width)
            Table(of: FileItem.self, selection: $selection, sortOrder: sortOrder) {
                TableColumn(L10n.Sort.name, value: \.name) { item in
                    MacBrowseNameCell(
                        item: item,
                        title: isPersonalSpace(item) ? L10n.Browse.myFiles : item.name,
                        glyph: isPersonalSpace(item) ? IconKit.person : IconKit.folderFill,
                        serverURL: shouldShowThumbnails ? serverURL : nil,
                        isRenaming: item.id == renamingItemID,
                        isCut: cutItemIDs.contains(item.id),
                        isOffline: offlineItemIDs.contains(item.id),
                        isFavorite: favoriteItemIDs.contains(item.id),
                        onRenameCommit: onRenameCommit,
                        onRenameCancel: onRenameCancel
                    )
                    .macBoardTableCell()
                    .opacity(opacity(for: item))
                }
                .width(min: MacBrowseTableMetrics.nameColumnCompactWidth)
                if columns.showsDate {
                    TableColumn(L10n.Sort.dateModified, value: \.dateModified) { item in
                        secondaryText(isPersonalSpace(item) || !item.hasKnownDate
                            ? L10n.Browse.noValue
                            : dateFormat.tableString(from: item.dateModified, now: .now))
                            .opacity(opacity(for: item))
                    }
                    .width(MacBrowseTableMetrics.dateColumnWidth)
                }
                if columns.showsSize {
                    TableColumn(L10n.Sort.size, value: \.size) { item in
                        secondaryText(FileSizeFormat.string(for: item, folderSize: folderSizes[item.id]))
                            .monospacedDigit()
                            .opacity(opacity(for: item))
                    }
                    .width(MacBrowseTableMetrics.sizeColumnWidth)
                }
                if columns.showsKind {
                    TableColumn(L10n.Sort.kind, value: \.kind) { item in
                        secondaryText(item.isDirectory ? L10n.FileInfo.navigationTitleFolder : item.kind.uppercased())
                            .opacity(opacity(for: item))
                    }
                    .width(MacBrowseTableMetrics.kindColumnWidth)
                }
            } rows: {
                if let personalSpace {
                    TableRow(personalSpace)
                }
                ForEach(items) { item in
                    TableRow(item)
                        .draggable(DraggedServerItem(
                            item: item,
                            serverURL: serverURL,
                            scope: scope,
                            filesClient: filesClient,
                            canExport: canExportFiles
                        ))
                        .dropDestination(for: MacRowDrop.self) { drops in
                            guard item.isDirectory else { return }
                            var ids: [FileItem.ID] = []
                            var foreign: [FileItem] = []
                            var files: [URL] = []
                            let receiver = DragOrigin.current(serverURL: serverURL, scope: scope)
                            for drop in drops {
                                switch drop {
                                case let .item(reference) where reference.id != item.id && reference.origin == receiver:
                                    if items[id: reference.id] != nil {
                                        ids.append(reference.id)
                                    } else if let dragged = reference.item, DropPathValidation.isSafe(dragged) {
                                        foreign.append(dragged)
                                    }
                                case let .file(url) where url.isFileURL: files.append(url)
                                default: break
                                }
                            }
                            if canDropOnFolders, !ids.isEmpty {
                                onDropOnFolder(ids, item)
                            }
                            if !foreign.isEmpty {
                                onDropForeignItemsOnFolder(foreign, item)
                            }
                            if canUploadToFolders, !files.isEmpty {
                                onFilesDroppedOnFolder(files, item)
                            }
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
            .background {
                MacTableRowScroller(
                    row: scrollTargetID.flatMap { items.index(id: $0) }.map { $0 + (personalSpace == nil ? 0 : 1) },
                    target: scrollTargetID,
                    onScrolled: onScrollTargetShown
                )
            }
            .macBoardTable(showsHeaders: !items.isEmpty || personalSpace != nil)
            .backgroundGradient()
            .macBrowseTableWidth($width)
            // The table's scroll view otherwise draws its header material up under the pinned title.
            .clipped()
            .focused($isFocused)
            .focusEffectDisabled()
            .focusedWhenOnTop($isFocused)
            .onChange(of: isPeeking) { _, isOpen in
                isFocused = !isOpen
            }
            // Finder conventions: Return renames, Delete deletes; Edit menu Cut/Copy/Paste/Select
            // All and ⌘I reach the selection through the focused value.
            .onKeyPress(.space) {
                guard renamingItemID == nil, selection.count == 1, item(for: selection.first) != nil else {
                    return .ignored
                }
                onPeek()
                return .handled
            }
            // Finder's ⌘↓ opens the selection. A key equivalent, since the table takes arrow
            // keys before `onKeyPress` sees them; live only while the table has focus.
            .macOpenShortcut(isEnabled: isFocused) {
                if selection.count == 1 {
                    keyboardActions.open()
                }
            }
            .onDeleteCommand {
                if renamingItemID == nil {
                    keyboardActions.delete()
                }
            }
            // While a name is being edited in place its field has focus inside the table, so the
            // Edit menu (⌘A, ⌘C, ⌘V, ⌘Z, ⌘⌫) must edit that text, not act on the files.
            .focusedValue(\.browseKeyboardActions, renamingItemID == nil ? keyboardActions : nil)
            .focusedSceneValue(
                \.duplicateBrowseSelection,
                renamingItemID == nil && !selection.isEmpty && keyboardActions.canDuplicate
                    ? FocusedMenuAction(perform: keyboardActions.duplicate)
                    : nil
            )
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

        private func secondaryText(_ text: String) -> some View {
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        /// The store owns the sort; the table only renders it and reports header clicks.
        private var sortOrder: Binding<[KeyPathComparator<FileItem>]> {
            Binding(
                get: { [sortOption.tableComparator(sortDirection)] },
                set: { newValue in
                    guard let first = newValue.first else { return }
                    let option = BrowseFeature.SortOption(tableComparator: first)
                    let direction: BrowseFeature.SortDirection = first.order == .forward ? .ascending : .descending
                    Task { @MainActor in onSortChanged(option, direction) }
                }
            )
        }
    }

    #Preview("Table") {
        @Previewable @State var selection: Set<FileItem.ID> = []
        let items: IdentifiedArrayOf<FileItem> = [
            FileItem(name: "Projects", path: "", dateModified: Date(), size: 0, kind: "directory"),
            FileItem(
                name: "report.pdf",
                path: "",
                dateModified: Date().addingTimeInterval(-86_400),
                size: 182_000,
                kind: "pdf"
            ),
            FileItem(
                name: "beach.jpg",
                path: "",
                dateModified: Date().addingTimeInterval(-86_400 * 9),
                size: 2_400_000,
                kind: "jpg"
            ),
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
            scope: "preview",
            canDropOnFolders: true,
            onDropOnFolder: { _, _ in },
            contextMenu: { _ in EmptyView() }
        )
        .previewCanvas(.table)
    }

#endif
