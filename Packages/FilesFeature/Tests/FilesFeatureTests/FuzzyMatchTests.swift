import Testing

@testable import FilesFeature

@Suite
struct FuzzyMatchTests {
    // MARK: Happy path

    @Test
    func exactMatchSucceeds() {
        #expect(FuzzyMatch.matches(query: "vacation", in: "vacation.jpg"))
    }

    @Test
    func inOrderSubsequenceMatchesEvenWhenNotContiguous() {
        #expect(FuzzyMatch.matches(query: "vjpg", in: "vacation.jpg"))
    }

    @Test
    func isCaseInsensitive() {
        #expect(FuzzyMatch.matches(query: "VACATION", in: "vacation.jpg"))
        #expect(FuzzyMatch.matches(query: "vacation", in: "VACATION.JPG"))
    }

    // MARK: Error / no-match path

    @Test
    func outOfOrderCharactersDoNotMatch() {
        #expect(!FuzzyMatch.matches(query: "gpj", in: "vacation.jpg"))
    }

    @Test
    func queryLongerThanTextDoesNotMatch() {
        #expect(!FuzzyMatch.matches(query: "vacationphoto", in: "vacation"))
    }

    @Test
    func aCharacterNotPresentInTextDoesNotMatch() {
        #expect(!FuzzyMatch.matches(query: "vacationz", in: "vacation.jpg"))
    }

    // MARK: Edge cases

    @Test
    func emptyQueryMatchesAnything() {
        #expect(FuzzyMatch.matches(query: "", in: "vacation.jpg"))
        #expect(FuzzyMatch.matches(query: "", in: ""))
    }

    @Test
    func emptyTextOnlyMatchesAnEmptyQuery() {
        #expect(!FuzzyMatch.matches(query: "a", in: ""))
    }

    @Test
    func repeatedCharactersInQueryRequireEnoughOccurrencesInText() {
        #expect(FuzzyMatch.matches(query: "aa", in: "banana"))
        #expect(!FuzzyMatch.matches(query: "aaaa", in: "banana"))
    }

    @Test
    func unicodeAndEmojiCharactersMatch() {
        #expect(FuzzyMatch.matches(query: "日本", in: "日本語ファイル"))
        #expect(FuzzyMatch.matches(query: "📷", in: "vacation📷.jpg"))
    }

    @Test
    func wholeQueryMatchingWholeTextIsAMatch() {
        #expect(FuzzyMatch.matches(query: "vacation.jpg", in: "vacation.jpg"))
    }
}
