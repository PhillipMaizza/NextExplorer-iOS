#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    struct MacPeekFolder: View {
        static let shownCount = 8

        let item: FileItem
        let serverURL: URL
        let shouldShowThumbnails: Bool
        let showsHiddenFiles: Bool

        @Dependency(\.filesClient) private var filesClient

        var body: some View {
            GalleryFetchedPage(
                isNear: true,
                failureMessage: L10n.EmptyState.loadFailed,
                fetch: { [filesClient, serverURL, path = item.id] in
                    try await filesClient.browse(serverURL, path).items
                },
                content: { listing($0) }
            )
        }

        @ViewBuilder
        private func listing(_ all: [FileItem]) -> some View {
            let items = Self.visible(all, showsHiddenFiles: showsHiddenFiles)
            if items.isEmpty {
                Text(L10n.EmptyState.folderEmpty)
                    .type(.body2(.regular), style: .secondary)
            } else {
                VStack(spacing: .space16) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: .space16),
                            count: MacPeekMetrics.columns
                        ),
                        spacing: .space16
                    ) {
                        ForEach(items.prefix(Self.shownCount)) { child in
                            GridCellView(item: child, serverURL: serverURL, shouldShowThumbnails: shouldShowThumbnails)
                        }
                    }
                    Text(Self.summary(items))
                        .type(.body3(.regular), style: .secondary)
                }
                .padding(.horizontal, .space24)
                .frame(maxHeight: .infinity)
            }
        }

        static func visible(_ items: [FileItem], showsHiddenFiles: Bool) -> [FileItem] {
            let shown = showsHiddenFiles ? items : items.filter { !isHiddenFileName($0.name) }
            return shown.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }

        static func summary(_ items: [FileItem]) -> String {
            let counts = FolderContentSummary.text(for: items) ?? ""
            let hidden = items.count - shownCount
            return hidden > 0 ? L10n.Browse.contentSummary(counts, L10n.FileInfo.moreSelected(hidden)) : counts
        }
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        static let folder = FileItem(
            name: "Contracts",
            path: "Documents",
            dateModified: .distantPast,
            size: 0,
            kind: "directory"
        )
    }

    #Preview("Folder") {
        MacPeekFolder(
            item: PreviewFixture.folder,
            serverURL: PreviewFixture.serverURL,
            shouldShowThumbnails: true,
            showsHiddenFiles: false
        )
        .frame(width: MacPeekMetrics.previewWidth, height: MacPeekMetrics.previewHeight)
        .background(Color.macCard)
    }
#endif
