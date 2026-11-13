import CoreModels
@testable import FilesFeature
import Localization
import Testing
import TestUtils

struct SearchResultDisplayTests {
    private enum Constants {
        static let kind = "file"
        static let codeLine = "func run() {}"
        static let noExtension = "Makefile"
        static let folderKind = "dir"
        static let unknownKind = "unknown"
        static let video = "clip.mp4"
    }

    private func hit(matchLine: String?, matchLineNumber: Int? = nil) -> SearchResultItem {
        SearchResultItem(
            name: TestFile.notes, path: TestFolder.docs, kind: Constants.kind, matchLine: matchLine, matchLineNumber: matchLineNumber
        )
    }

    struct SnippetCase: Sendable {
        let matchLine: String?
        let expected: String?
    }

    nonisolated static let snippetCases = [
        SnippetCase(matchLine: nil, expected: nil),
        SnippetCase(matchLine: "", expected: nil),
        SnippetCase(matchLine: "   \t\n", expected: nil),
        SnippetCase(matchLine: "    \tfunc run() {}  \n", expected: "func run() {}"),
        SnippetCase(matchLine: "inner  spacing kept", expected: "inner  spacing kept"),
    ]

    @Test(arguments: snippetCases)
    func theSnippetIsTheTrimmedMatchedLineOrNilWhenThereIsNothingToShow(_ testCase: SnippetCase) {
        #expect(searchResultSnippet(hit(matchLine: testCase.matchLine)) == testCase.expected)
    }

    @Test
    func theLineLabelNeedsBothAMatchedLineAndItsNumber() {
        #expect(searchResultLineLabel(hit(matchLine: Constants.codeLine, matchLineNumber: 12)) == L10n.Browse.searchMatchLineLabel(12))
        #expect(searchResultLineLabel(hit(matchLine: Constants.codeLine, matchLineNumber: nil)) == nil)
        #expect(searchResultLineLabel(hit(matchLine: nil, matchLineNumber: 12)) == nil)
    }

    @Test
    func theLineLabelIsStillShownForAWhitespaceOnlyMatchedLine() {
        #expect(searchResultLineLabel(hit(matchLine: "   ", matchLineNumber: 3)) == L10n.Browse.searchMatchLineLabel(3))
    }

    @Test("A row says what matched only when it is more than the name, a Mac column always does")
    func theMatchLabelSaysMoreThanTheName() {
        let nameOnly = SearchResultItem(name: TestFile.notes, path: TestFolder.docs, kind: Constants.kind, isNameMatch: true)
        let contents = SearchResultItem(
            name: TestFile.notes, path: TestFolder.docs, kind: Constants.kind,
            matchLine: Constants.codeLine, matchLineNumber: 12, isContentMatch: true
        )
        let both = SearchResultItem(
            name: TestFile.notes, path: TestFolder.docs, kind: Constants.kind,
            matchLine: Constants.codeLine, matchLineNumber: 3, isNameMatch: true, isContentMatch: true
        )
        let instant = SearchResultItem(name: TestFile.notes, path: TestFolder.docs, kind: Constants.kind)

        #expect(searchResultRowLabel(nameOnly) == nil)
        #expect(searchResultMatchDescription(nameOnly) == L10n.Browse.searchMatchedByName)
        #expect(searchResultRowLabel(contents) == "\(L10n.Browse.searchMatchedByContent), \(L10n.Browse.searchMatchLineLabel(12))")
        #expect(searchResultRowLabel(both) == "\(L10n.Browse.searchMatchedByBoth), \(L10n.Browse.searchMatchLineLabel(3))")
        #expect(searchResultRowLabel(instant) == nil)
        #expect(searchResultMatchDescription(instant) == nil)
    }

    @Test("A file hit takes its kind from its name, a folder keeps its own")
    func aHitsKindComesFromItsName() {
        #expect(SearchResultItem(name: TestFile.vacationPhoto, path: "", kind: Constants.kind).displayKind == TestKind.photo)
        #expect(SearchResultItem(name: Constants.noExtension, path: "", kind: Constants.kind).displayKind == "")
        #expect(SearchResultItem(name: TestFolder.photos, path: "", kind: Constants.folderKind).displayKind == Constants.folderKind)
    }

    @Test("A file hit opens like a tapped row, and one without an extension opens as unknown")
    func aFileHitOpensLikeARow() {
        let photo = SearchResultItem(name: TestFile.vacationPhoto, path: TestFolder.photos, kind: Constants.kind).previewItem(openedAt: MockDate.date)
        let bare = SearchResultItem(name: Constants.noExtension, path: TestFolder.docs, kind: Constants.kind).previewItem(openedAt: MockDate.date)

        #expect(photo == FileItem(name: TestFile.vacationPhoto, path: TestFolder.photos, dateModified: MockDate.date, size: 0, kind: TestKind.photo, supportsThumbnail: false))
        #expect(bare.kind == Constants.unknownKind)
    }

    @Test("Pictures and videos ask the server for a thumbnail, other files and folders do not")
    func onlyThumbnailableHitsAskForOne() {
        #expect(SearchResultItem(name: TestFile.vacationPhoto, path: "", kind: Constants.kind).thumbnailFile?.supportsThumbnail == true)
        #expect(SearchResultItem(name: Constants.video, path: "", kind: Constants.kind).thumbnailFile?.supportsThumbnail == true)
        #expect(SearchResultItem(name: TestFile.notes, path: "", kind: Constants.kind).thumbnailFile?.supportsThumbnail == false)
        #expect(SearchResultItem(name: TestFolder.photos, path: "", kind: Constants.folderKind).thumbnailFile == nil)
    }

    @Test("A hit at the top lives in the root, any other in its folder")
    func theEnclosingFolderIsNamed() {
        #expect(SearchResultItem(name: TestFile.notes, path: "", kind: Constants.kind).enclosingFolderTitle == L10n.Browse.navigationTitle)
        #expect(SearchResultItem(name: TestFile.notes, path: TestPath.documentsWork, kind: Constants.kind).enclosingFolderTitle == FilesFeatureTestValue.workFolder)
    }
}
