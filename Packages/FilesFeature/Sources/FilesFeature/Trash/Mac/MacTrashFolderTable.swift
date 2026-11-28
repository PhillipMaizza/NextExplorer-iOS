#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacTrashFolderTable: View {
        let store: StoreOf<TrashFolderFeature>

        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        @State private var selection: Set<TrashEntry.ID> = []
        @State private var width = CGFloat.infinity
        @FocusState private var isFocused: Bool

        var body: some View {
            let columns = MacBrowseTableColumns(width: width)
            Table(store.entries, selection: $selection) {
                TableColumn(L10n.Sort.name) { entry in
                    HStack(spacing: .space8) {
                        MacItemTile(name: entry.name, isDirectory: entry.isDirectory)
                        MacFileNameText(name: entry.name, isDirectory: entry.isDirectory)
                        if entry.shareCount > 0 {
                            MacTableFolderIcon(
                                image: IconKit.shareLink,
                                tint: .accent,
                                size: MacBrowseTableMetrics.badgeSize
                            )
                            .accessibilityLabel(L10n.Trash.sharesBadge)
                        }
                    }
                    .macBoardTableCell()
                }
                .width(min: MacBrowseTableMetrics.nameColumnCompactWidth)
                if columns.showsDate {
                    TableColumn(L10n.Sort.dateModified) { entry in
                        secondaryText(entry.modifiedAt.map { dateFormat.tableString(from: $0, now: .now) } ?? "")
                    }
                    .width(MacBrowseTableMetrics.dateColumnWidth)
                }
                if columns.showsSize {
                    TableColumn(L10n.Sort.size) { entry in
                        secondaryText(entry.isDirectory
                            ? L10n.Browse.noValue
                            : entry.size.map(FileSizeFormat.string) ?? "")
                            .monospacedDigit()
                    }
                    .width(MacBrowseTableMetrics.sizeColumnWidth)
                }
                if columns.showsKind {
                    TableColumn(L10n.Sort.kind) { entry in
                        secondaryText(entry.isDirectory
                            ? L10n.FileInfo.navigationTitleFolder
                            : TrashRowText.kind(entry.name, isDirectory: false).uppercased())
                    }
                    .width(MacBrowseTableMetrics.kindColumnWidth)
                }
            }
            .contextMenu(forSelectionType: TrashEntry.ID.self) { ids in
                let picked = entries(ids)
                if !picked.isEmpty {
                    Button { store.send(.restoreTapped(picked)) } label: {
                        Label { Text(L10n.Trash.restore) } icon: { IconKit.restore }
                    }
                    Button { store.send(.restoreToTapped(picked)) } label: {
                        Label { Text(L10n.Trash.restoreTo) } icon: { IconKit.restoreTo }
                    }
                }
            } primaryAction: { ids in
                open(ids)
            }
            .macOpenShortcut(isEnabled: isFocused) { open(selection) }
            .labelStyle(.titleAndIcon)
            .macBoardTable()
            .backgroundGradient()
            .macBrowseTableWidth($width)
            .clipped()
            .focused($isFocused)
            .focusEffectDisabled()
            .focusedWhenOnTop($isFocused)
            .disabled(store.restore.isRestoring)
            .onChange(of: store.entries) { _, entries in
                selection.formIntersection(entries.map(\.id))
            }
        }

        private var dateFormat: DateDisplayFormat {
            DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
        }

        private func open(_ ids: Set<TrashEntry.ID>) {
            if ids.count == 1, let entry = entries(ids).first {
                store.send(.entryTapped(entry))
            }
        }

        private func entries(_ ids: Set<TrashEntry.ID>) -> [TrashEntry] {
            store.entries.filter { ids.contains($0.id) }
        }

        private func secondaryText(_ text: String) -> some View {
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    #Preview("Folder") {
        MacTrashFolderTable(store: TrashPreviewData.folder())
            .frame(width: 900, height: 400)
    }

    #Preview("Folder, dark") {
        MacTrashFolderTable(store: TrashPreviewData.folder())
            .frame(width: 900, height: 400)
            .preferredColorScheme(.dark)
    }
#endif
