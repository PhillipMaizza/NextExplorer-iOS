@testable import FilesFeature
import Testing
import TestUtils

struct SearchMatchTests {
    // MARK: Happy path

    @Test
    func contiguousSubstringMatchesAnywhereInTheName() {
        #expect(SearchMatch.matches(query: "cat", in: TestFile.vacationPhoto))
        #expect(SearchMatch.matches(query: ".jpg", in: TestFile.vacationPhoto))
    }

    @Test
    func isCaseInsensitive() {
        #expect(SearchMatch.matches(query: "VACATION", in: TestFile.vacationPhoto))
        #expect(SearchMatch.matches(query: "vacation", in: "VACATION.JPG"))
        #expect(SearchMatch.matches(query: "Cat", in: "vaCATion.jpg"))
    }

    // MARK: Error / no-match path

    @Test
    func aScatteredSubsequenceDoesNotMatch() {
        // Matches the backend `.includes` contract: only a contiguous run counts, not a
        // command-palette style subsequence.
        #expect(!SearchMatch.matches(query: "vjpg", in: TestFile.vacationPhoto))
        #expect(!SearchMatch.matches(query: "vcto", in: TestFile.vacationPhoto))
    }

    @Test
    func aCharacterNotPresentInTextDoesNotMatch() {
        #expect(!SearchMatch.matches(query: "vacationz", in: TestFile.vacationPhoto))
    }

    // MARK: Edge cases

    @Test
    func emptyOrWhitespaceQueryMatchesAnything() {
        #expect(SearchMatch.matches(query: "", in: TestFile.vacationPhoto))
        #expect(SearchMatch.matches(query: TestValue.blank, in: TestFile.vacationPhoto))
        #expect(SearchMatch.matches(query: "", in: ""))
    }

    @Test
    func leadingAndTrailingWhitespaceIsTrimmedBeforeMatching() {
        #expect(SearchMatch.matches(query: "  cat  ", in: TestFile.vacationPhoto))
    }

    @Test
    func emptyTextOnlyMatchesAnEmptyQuery() {
        #expect(!SearchMatch.matches(query: "a", in: ""))
    }

    @Test
    func unicodeAndEmojiSubstringsMatch() {
        #expect(SearchMatch.matches(query: "日本", in: "日本語ファイル"))
        #expect(SearchMatch.matches(query: "📷", in: "vacation📷.jpg"))
    }

    @Test
    func wholeQueryMatchingWholeTextIsAMatch() {
        #expect(SearchMatch.matches(query: TestFile.vacationPhoto, in: TestFile.vacationPhoto))
    }
}
