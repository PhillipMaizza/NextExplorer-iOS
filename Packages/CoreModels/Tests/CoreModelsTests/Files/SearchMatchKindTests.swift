@testable import CoreModels
import Testing
import TestUtils

@Suite("SearchResultItem matchKind")
struct SearchMatchKindTests {
    private struct Case: Sendable, CustomTestStringConvertible {
        let isNameMatch: Bool?
        let isContentMatch: Bool?
        let matchLine: String?
        let expected: SearchMatchKind?

        var testDescription: String {
            "name \(String(describing: isNameMatch)) content \(String(describing: isContentMatch)) line \(String(describing: matchLine))"
        }
    }

    private static let cases = [
        Case(isNameMatch: true, isContentMatch: true, matchLine: nil, expected: .both),
        Case(isNameMatch: true, isContentMatch: nil, matchLine: "hit", expected: .both),
        Case(isNameMatch: true, isContentMatch: false, matchLine: nil, expected: .name),
        Case(isNameMatch: true, isContentMatch: nil, matchLine: nil, expected: .name),
        Case(isNameMatch: false, isContentMatch: true, matchLine: nil, expected: .contents),
        Case(isNameMatch: nil, isContentMatch: nil, matchLine: "hit", expected: .contents),
        Case(isNameMatch: false, isContentMatch: false, matchLine: "hit", expected: .contents),
        Case(isNameMatch: false, isContentMatch: false, matchLine: nil, expected: nil),
        Case(isNameMatch: nil, isContentMatch: nil, matchLine: nil, expected: nil),
    ]

    @Test("the match half is derived from the server flags and the presence of a match line", arguments: cases)
    private func derivesMatchKind(_ testCase: Case) {
        let item = SearchResultItem(
            name: TestFile.notes,
            path: TestFolder.docs,
            kind: TestKind.text,
            matchLine: testCase.matchLine,
            isNameMatch: testCase.isNameMatch,
            isContentMatch: testCase.isContentMatch
        )
        #expect(item.matchKind == testCase.expected)
    }
}
