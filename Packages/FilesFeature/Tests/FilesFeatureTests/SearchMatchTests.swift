@testable import FilesFeature
import Testing

struct SearchMatchTests {
    // MARK: Happy path

    @Test
    func exactMatchSucceeds() {
        #expect(SearchMatch.matches(query: "vacation", in: "vacation.jpg"))
    }

    @Test
    func contiguousSubstringMatchesAnywhereInTheName() {
        #expect(SearchMatch.matches(query: "cat", in: "vacation.jpg"))
        #expect(SearchMatch.matches(query: ".jpg", in: "vacation.jpg"))
    }

    @Test
    func isCaseInsensitive() {
        #expect(SearchMatch.matches(query: "VACATION", in: "vacation.jpg"))
        #expect(SearchMatch.matches(query: "vacation", in: "VACATION.JPG"))
        #expect(SearchMatch.matches(query: "Cat", in: "vaCATion.jpg"))
    }

    // MARK: Error / no-match path

    @Test
    func aScatteredSubsequenceDoesNotMatch() {
        // Matches the backend `.includes` contract: only a contiguous run counts, not a
        // command-palette style subsequence.
        #expect(!SearchMatch.matches(query: "vjpg", in: "vacation.jpg"))
        #expect(!SearchMatch.matches(query: "vcto", in: "vacation.jpg"))
    }

    @Test
    func outOfOrderCharactersDoNotMatch() {
        #expect(!SearchMatch.matches(query: "gpj", in: "vacation.jpg"))
    }

    @Test
    func queryLongerThanTextDoesNotMatch() {
        #expect(!SearchMatch.matches(query: "vacationphoto", in: "vacation"))
    }

    @Test
    func aCharacterNotPresentInTextDoesNotMatch() {
        #expect(!SearchMatch.matches(query: "vacationz", in: "vacation.jpg"))
    }

    // MARK: Edge cases

    @Test
    func emptyOrWhitespaceQueryMatchesAnything() {
        #expect(SearchMatch.matches(query: "", in: "vacation.jpg"))
        #expect(SearchMatch.matches(query: "   ", in: "vacation.jpg"))
        #expect(SearchMatch.matches(query: "", in: ""))
    }

    @Test
    func leadingAndTrailingWhitespaceIsTrimmedBeforeMatching() {
        #expect(SearchMatch.matches(query: "  cat  ", in: "vacation.jpg"))
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
        #expect(SearchMatch.matches(query: "vacation.jpg", in: "vacation.jpg"))
    }
}
