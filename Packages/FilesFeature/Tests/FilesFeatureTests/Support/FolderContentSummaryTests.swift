import DesignSystem
@testable import FilesFeature
import Localization
import Testing

struct FolderContentSummaryTests {
    @Test
    func summaryNamesOnlyTheKindsPresent() {
        #expect(FolderContentSummary.text(folders: 0, files: 0) == nil)
        #expect(FolderContentSummary.text(folders: 2, files: 0) == L10n.Browse.folderCount(2))
        #expect(FolderContentSummary.text(folders: 0, files: 13) == L10n.Browse.fileCount(13))
        #expect(
            FolderContentSummary.text(folders: 1, files: 13)
                == L10n.Browse.contentSummary(L10n.Browse.folderCount(1), L10n.Browse.fileCount(13))
        )
    }

    @Test
    func crumbsNameEveryFolderOnThePathAndThePersonalRoot() {
        #expect(FolderContentSummary.crumbs(for: "").isEmpty)
        #expect(FolderContentSummary.crumbs(for: "Files/Documents") == [
            PathCrumb(title: "Files", path: "Files"),
            PathCrumb(title: "Documents", path: "Files/Documents"),
        ])
        #expect(FolderContentSummary.crumbs(for: "personal/Documents").map(\.title) == [
            L10n.Browse.myFiles,
            "Documents",
        ])
    }
}
