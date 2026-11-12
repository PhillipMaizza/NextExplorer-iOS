import FilesClient
import Testing

/// A typed query read the way `GET /api/search` reads `q`: trimmed, and long enough by
/// JavaScript's `length` (UTF16 code units).
@Suite("Search term")
struct SearchTermTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let query: String
        let text: String
        let isSearchable: Bool
        let isTooShort: Bool
        var testDescription: String {
            "\"\(query)\""
        }
    }

    private static let cases = [
        Case(query: "", text: "", isSearchable: false, isTooShort: false),
        Case(query: " \n\t ", text: "", isSearchable: false, isTooShort: false),
        Case(query: "ab", text: "ab", isSearchable: false, isTooShort: true),
        Case(query: "  ab  ", text: "ab", isSearchable: false, isTooShort: true),
        Case(query: "abc", text: "abc", isSearchable: true, isTooShort: false),
        Case(query: " report \n", text: "report", isSearchable: true, isTooShort: false),
        Case(query: "a b", text: "a b", isSearchable: true, isTooShort: false),
        // Two emoji are four UTF16 units, which the server accepts.
        Case(query: "👍👍", text: "👍👍", isSearchable: true, isTooShort: false),
        // One emoji is two units, which it refuses.
        Case(query: "👍", text: "👍", isSearchable: false, isTooShort: true),
        // An accent typed as its own mark counts as its own unit, as on the server.
        Case(query: "e\u{301}e", text: "e\u{301}e", isSearchable: true, isTooShort: false),
        Case(query: "日本", text: "日本", isSearchable: false, isTooShort: true),
    ]

    @Test("A query is trimmed and counted like the server counts it", arguments: cases)
    func aQueryIsReadLikeTheServer(_ testCase: Case) {
        let term = SearchTerm(testCase.query)

        #expect(term.text == testCase.text)
        #expect(term.isEmpty == testCase.text.isEmpty)
        #expect(term.isSearchable == testCase.isSearchable)
        #expect(term.isTooShort == testCase.isTooShort)
    }

    @Test("Queries that differ only by surrounding spaces are the same term")
    func surroundingSpacesMakeTheSameTerm() {
        #expect(SearchTerm("vac ") == SearchTerm("vac"))
        #expect(SearchTerm(" vac") == SearchTerm("vac"))
        #expect(SearchTerm("va c") != SearchTerm("vac"))
        #expect(SearchTerm("Vac") != SearchTerm("vac"))
    }
}
