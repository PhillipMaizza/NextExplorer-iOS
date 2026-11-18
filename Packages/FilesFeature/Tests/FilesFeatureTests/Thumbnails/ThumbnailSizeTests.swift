import ComposableArchitecture
import CoreGraphics
import CoreModels
@testable import FilesFeature
import Testing

struct ThumbnailSizeTests {
    struct Metrics: Sendable {
        let size: ThumbnailSize
        let columnCount: Int
        let folderColumnCount: Int
    }

    nonisolated static let metrics = [
        Metrics(size: .small, columnCount: 4, folderColumnCount: 3),
        Metrics(size: .medium, columnCount: 3, folderColumnCount: 2),
        Metrics(size: .large, columnCount: 2, folderColumnCount: 2),
    ]

    @Test(arguments: metrics)
    func eachSizeHasItsFilesPerRow(_ metrics: Metrics) {
        #expect(metrics.size.columnCount == metrics.columnCount)
        #expect(FileGridMetrics.columns(for: .files, size: metrics.size, isCompact: true).count == metrics.columnCount)
    }

    @Test(arguments: metrics)
    func foldersFollowTheSizeOnAPhone(_ metrics: Metrics) {
        #expect(metrics.size.folderColumnCount == metrics.folderColumnCount)
        let columns = FileGridMetrics.columns(for: .folders, size: metrics.size, isCompact: true)
        #expect(columns.count == metrics.folderColumnCount)
    }

    @Test(arguments: metrics)
    func aRegularWidthGridAddsColumnsAsTheWidthAllows(_ metrics: Metrics) {
        #expect(FileGridMetrics.columns(for: .files, size: metrics.size, isCompact: false).count == 1)
    }

    @Test
    func biggerSizesGetWiderColumns() {
        #expect(ThumbnailSize.small.minimumColumnWidth < ThumbnailSize.medium.minimumColumnWidth)
        #expect(ThumbnailSize.medium.minimumColumnWidth < ThumbnailSize.large.minimumColumnWidth)
        #expect(ThumbnailSize.small.minimumFolderColumnWidth < ThumbnailSize.large.minimumFolderColumnWidth)
        #expect(ThumbnailSize.allCases.filter(\.isRoomy) == [.large])
        #expect(ThumbnailSize.allCases.filter(\.isDense) == [.small])
    }

    @Test
    func theStoredRawValuesAreStable() {
        #expect(ThumbnailSize.allCases.map(\.rawValue) == ["small", "medium", "large"])
        #expect(ThumbnailSize(rawValue: "huge") == nil)
    }

    @Test
    func theGridPutsFoldersBeforeFilesInTheirOwnOrder() {
        let items: IdentifiedArrayOf<FileItem> = [
            FileItem(name: "b", path: "", dateModified: .distantPast, size: 0, kind: FileItem.directoryKind),
            FileItem(name: "a", path: "", dateModified: .distantPast, size: 0, kind: FileItem.directoryKind),
            FileItem(name: "z.txt", path: "", dateModified: .distantPast, size: 1, kind: "txt"),
            FileItem(name: "c.txt", path: "", dateModified: .distantPast, size: 1, kind: "txt"),
        ]
        let groups = BrowseGridGroups(items: items)
        #expect(groups.folders.map(\.name) == ["b", "a"])
        #expect(groups.files.map(\.name) == ["z.txt", "c.txt"])
    }
}
