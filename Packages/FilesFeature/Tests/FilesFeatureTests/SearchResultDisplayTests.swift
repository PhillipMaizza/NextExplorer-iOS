import CoreModels
@testable import FilesFeature
import Localization
import Testing
import TestUtils

struct SearchResultDisplayTests {
    private enum Constants {
        static let kind = "file"
        static let codeLine = "func run() {}"
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
}
