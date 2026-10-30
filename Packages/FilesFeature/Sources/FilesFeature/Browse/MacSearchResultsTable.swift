#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let locationColumnMinWidth: CGFloat = 200
    }

    /// Browse search results as a Mac table, like the folder it searches: the name with the
    /// matched line under it, and where the hit lives. Double click or Return opens it.
    struct MacSearchResultsTable: View {
        let results: [SearchResultItem]
        let favoritePaths: Set<String>
        let onOpen: (SearchResultItem) -> Void

        @State private var selection: Set<SearchResultItem.ID> = []

        var body: some View {
            Table(results, selection: $selection) {
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
                            MacTableFolderIcon(image: IconKit.starFill, tint: Color.accent, size: MacBrowseTableMetrics.badgeSize)
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
            }
            .contextMenu(forSelectionType: SearchResultItem.ID.self, menu: { _ in }, primaryAction: { ids in
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

    #Preview("Results") {
        MacSearchResultsTable(
            results: [
                SearchResultItem(name: "Trips", path: "Photos", kind: "dir"),
                SearchResultItem(name: "Beach.jpg", path: "Photos/Trips", kind: "file"),
                SearchResultItem(name: "Quarterly Report.txt", path: "Documents", kind: "file", matchLine: "    vacation budget", matchLineNumber: 12),
            ],
            favoritePaths: ["Photos/Trips"],
            onOpen: { _ in }
        )
        .previewCanvas(.table)
    }
#endif
