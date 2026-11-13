#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let locationColumnMinWidth: CGFloat = 200
        static let matchColumnMinWidth: CGFloat = 90
    }

    /// Browse search results as a Mac table, like the folder it searches: the name with the
    /// matched line under it, and where the hit lives. Double click or Return opens it. Results kept
    /// on this device head the table under "On device", the rest follow under "Remote".
    struct MacSearchResultsTable: View {
        let sections: SearchResultSections
        let favoritePaths: Set<String>
        let onOpen: (SearchResultItem) -> Void
        var onShowInFolder: (SearchResultItem) -> Void = { _ in }

        @State private var selection: Set<SearchResultItem.ID> = []

        private var results: [SearchResultItem] {
            sections.onDevice + sections.remote
        }

        var body: some View {
            Table(of: SearchResultItem.self, selection: $selection) {
                TableColumn(L10n.Sort.name) { result in
                    HStack(spacing: .space8) {
                        icon(for: result)
                        VStack(alignment: .leading, spacing: .space2) {
                            Text(result.name).lineLimit(1).truncationMode(.middle)
                            if let snippet = searchResultSnippet(result) {
                                Text(snippet)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if favoritePaths.contains(result.id) {
                            MacTableFolderIcon(
                                image: IconKit.starFill,
                                tint: Color.accent,
                                size: MacBrowseTableMetrics.badgeSize
                            )
                            .accessibilityLabel(L10n.Favorites.accessibilityBadge)
                        }
                    }
                    .padding(.vertical, MacBrowseTableMetrics.rowVerticalPadding)
                }
                .width(min: MacBrowseTableMetrics.nameColumnMinWidth)
                TableColumn(L10n.FileInfo.rowLocation) { result in
                    Text(result.path.isEmpty ? "/" : result.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                }
                .width(min: Metrics.locationColumnMinWidth)
                TableColumn(L10n.Browse.searchMatchColumn) { result in
                    Text(searchResultMatchDescription(result) ?? "")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .width(min: Metrics.matchColumnMinWidth)
            } rows: {
                if sections.isSplit {
                    Section(L10n.Search.onDevice) {
                        ForEach(sections.onDevice) { TableRow($0) }
                    }
                    if !sections.remote.isEmpty {
                        Section(L10n.Search.remote) {
                            ForEach(sections.remote) { TableRow($0) }
                        }
                    }
                } else {
                    ForEach(sections.remote) { TableRow($0) }
                }
            }
            .contextMenu(forSelectionType: SearchResultItem.ID.self, menu: { ids in
                // Finder's search results menu: open the hit, show where it lives, copy its path.
                if ids.count == 1, let result = results.first(where: { $0.id == ids.first }) {
                    SearchResultMenu(
                        result: result,
                        onOpen: { onOpen(result) },
                        onShowInFolder: { onShowInFolder(result) }
                    )
                    .labelStyle(.titleAndIcon)
                }
            }, primaryAction: { ids in
                guard ids.count == 1, let result = results.first(where: { $0.id == ids.first }) else { return }
                onOpen(result)
            })
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
        }

        private func icon(for result: SearchResultItem) -> some View {
            Group {
                if result.isDirectory {
                    MacTableFolderIcon(image: IconKit.folderFill, tint: Color.accent)
                } else {
                    FileTypeIcon(kind: (result.name as NSString).pathExtension.lowercased())
                        .frame(width: MacBrowseTableMetrics.iconSize, height: MacBrowseTableMetrics.iconSize)
                }
            }
            .accessibilityHidden(true)
        }
    }

    #Preview("Results, one on the device") {
        MacSearchResultsTable(
            sections: SearchResultSections([
                SearchResultItem(name: "Trips", path: "Photos", kind: "dir", isNameMatch: true),
                SearchResultItem(
                    name: "Beach.jpg",
                    path: "Photos/Trips",
                    kind: "file",
                    isNameMatch: true,
                    isContentMatch: true
                ),
                SearchResultItem(
                    name: "Quarterly Report.txt", path: "Documents", kind: "file",
                    matchLine: "    vacation budget", matchLineNumber: 12, isNameMatch: false, isContentMatch: true
                ),
            ], onDeviceIDs: ["Photos/Trips/Beach.jpg"]),
            favoritePaths: ["Photos/Trips"],
            onOpen: { _ in }
        )
        .previewCanvas(.table)
    }

    #Preview("Empty") {
        MacSearchResultsTable(sections: SearchResultSections([], onDeviceIDs: []), favoritePaths: [], onOpen: { _ in })
            .previewCanvas(.table)
    }
#endif
