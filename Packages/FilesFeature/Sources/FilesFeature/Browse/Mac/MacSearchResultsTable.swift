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
    struct MacSearchResultsTable<FileActions: View>: View {
        let sections: SearchResultSections
        var elsewhere: [SearchResultItem] = []
        var elsewhereNote: AttributedString?
        var lanes: [SearchLane] = []
        let favoritePaths: Set<String>
        var serverURL: URL?
        let onOpen: (SearchResultItem) -> Void
        @ViewBuilder var fileActions: (SearchResultItem) -> FileActions

        @State private var selection: Set<SearchResultItem.ID> = []
        @State private var sortOrder: [KeyPathComparator<SearchResultItem>] = []

        private var results: [SearchResultItem] {
            sections.onDevice + sections.remote + elsewhere + lanes.flatMap(\.rows)
        }

        var body: some View {
            Table(of: SearchResultItem.self, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(L10n.Sort.name, value: \.name) { result in
                    HStack(spacing: .space8) {
                        icon(for: result)
                        VStack(alignment: .leading, spacing: .space2) {
                            MacFileNameText(name: result.name, isDirectory: result.isDirectory)
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
                    .macBoardTableCell()
                }
                .width(min: MacBrowseTableMetrics.nameColumnMinWidth)
                TableColumn(L10n.FileInfo.rowLocation, value: \.path) { result in
                    Text(MacInspectorLocation.trail(parent: result.path))
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
                if !lanes.isEmpty {
                    ForEach(lanes.filter(\.isShown)) { lane in
                        Section {
                            ForEach(sorted(lane.rows)) { TableRow($0) }
                        } header: {
                            MacSearchLaneHeader(lane: lane)
                        }
                    }
                } else if sections.isSplit {
                    Section(L10n.Search.onDevice) {
                        ForEach(sorted(sections.onDevice)) { TableRow($0) }
                    }
                    if !sections.remote.isEmpty {
                        Section(L10n.Search.remote) {
                            ForEach(sorted(sections.remote)) { TableRow($0) }
                        }
                    }
                } else {
                    ForEach(sorted(sections.remote)) { TableRow($0) }
                }
                if !elsewhere.isEmpty {
                    Section {
                        ForEach(sorted(elsewhere)) { TableRow($0) }
                    } header: {
                        MacElsewhereSectionHeader(note: elsewhereNote, count: elsewhere.count)
                    }
                }
            }
            .contextMenu(forSelectionType: SearchResultItem.ID.self, menu: { ids in
                // Finder's search results menu: open the hit, show where it lives, copy its path.
                if ids.count == 1, let result = results.first(where: { $0.id == ids.first }) {
                    fileActions(result)
                        .labelStyle(.titleAndIcon)
                }
            }, primaryAction: { ids in
                guard ids.count == 1, let result = results.first(where: { $0.id == ids.first }) else { return }
                onOpen(result)
            })
            .macBoardTable()
        }

        private func sorted(_ results: [SearchResultItem]) -> [SearchResultItem] {
            sortOrder.isEmpty ? results : results.sorted(using: sortOrder)
        }

        @ViewBuilder
        private func icon(for result: SearchResultItem) -> some View {
            if let file = result.thumbnailFile {
                MacFileTile(item: file, serverURL: serverURL)
            } else {
                MacItemTile(name: result.name, isDirectory: result.isDirectory)
            }
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
            serverURL: URL(string: "https://cloud.example.com"),
            onOpen: { _ in },
            fileActions: { _ in EmptyView() }
        )
        .previewCanvas(.table)
    }

    #Preview("Empty") {
        MacSearchResultsTable(
            sections: SearchResultSections([], onDeviceIDs: []),
            favoritePaths: [],
            onOpen: { _ in },
            fileActions: { _ in EmptyView() }
        )
        .previewCanvas(.table)
    }
#endif
