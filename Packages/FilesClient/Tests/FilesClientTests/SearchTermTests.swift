import CoreModels
import FilesClient
import Testing
import TestUtils

/// A typed query read the way `GET /api/search` reads `q`: trimmed, and long enough by
/// JavaScript's `length` (UTF16 code units).
@Suite("Search term")
struct SearchTermTests {
    private enum Constants {
        static let imageGlob = "IMG_????.jpg"
        static let literalGlob = "a+b*"
        static let photos = "photos"
        static let archive = "Archive"
        static let z = "Z"
        static let pathGlob = "Stacks/*.log"
        static let stacks = "Stacks"
        static let log = "app.log"
        static let stacksLog = "Stacks/app.log"
        static let otherLog = "Other/app.log"
    }

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
        #expect(SearchTerm(TestSearch.term + " ") == SearchTerm(TestSearch.term))
        #expect(SearchTerm(" " + TestSearch.term) == SearchTerm(TestSearch.term))
        #expect(SearchTerm("va c") != SearchTerm(TestSearch.term))
        #expect(SearchTerm("Vac") != SearchTerm(TestSearch.term))
    }

    @Test("A name holds the term case insensitively, anywhere, and an empty term matches every name")
    func aNameHoldsTheTerm() {
        #expect(SearchTerm(" Pho ").matches(Constants.photos))
        #expect(SearchTerm("TOS").matches(Constants.photos))
        #expect(SearchTerm("").matches(Constants.photos))
        #expect(SearchTerm("   ").matches(""))
        #expect(!SearchTerm("pts").matches(Constants.photos))
        #expect(!SearchTerm("x").matches(""))
    }

    struct MatchCase: Sendable, CustomTestStringConvertible {
        let term: String
        let name: String
        let matches: Bool
        var testDescription: String {
            "\"\(term)\" against \"\(name)\""
        }
    }

    private static let matchCases = [
        // A shape for names: the whole name must fit, case aside.
        MatchCase(term: TestSearch.pdfGlob, name: "Report.PDF", matches: true),
        MatchCase(term: TestSearch.pdfGlob, name: "pdf.txt", matches: false),
        MatchCase(term: TestSearch.pdfGlob, name: "a.pdf.zip", matches: false),
        MatchCase(term: Constants.imageGlob, name: "IMG_0042.JPG", matches: true),
        MatchCase(term: Constants.imageGlob, name: "IMG_42.jpg", matches: false),
        // Everything but `*` and `?` is itself, never an expression.
        MatchCase(term: Constants.literalGlob, name: "a+b.txt", matches: true),
        MatchCase(term: Constants.literalGlob, name: "aab.txt", matches: false),
        MatchCase(term: "(1)*", name: "(1) copy.txt", matches: true),
        // Text is looked for anywhere, case aside.
        MatchCase(term: "VAC", name: "vacation.jpg", matches: true),
        // The same letters spelled composed or decomposed are the same letters.
        MatchCase(term: "r\u{E9}sum\u{E9}", name: "Re\u{301}sume\u{301}.pdf", matches: true),
        MatchCase(term: "re\u{301}sume\u{301}", name: "R\u{E9}sum\u{E9}.pdf", matches: true),
        MatchCase(term: "r*sum\u{E9}.pdf", name: "Re\u{301}sume\u{301}.pdf", matches: true),
        // A path shape fits no single name.
        MatchCase(term: Constants.pathGlob, name: Constants.stacks, matches: false),
    ]

    @Test("A name answers a term as the server decides it", arguments: matchCases)
    func aNameAnswersLikeTheServer(_ testCase: MatchCase) {
        #expect(SearchTerm(testCase.term).matches(testCase.name) == testCase.matches)
    }

    @Test("A path shape is matched against the path below the search's folder, and never by a folder")
    func aPathShapeMatchesFilesByTheirPath() {
        let term = SearchTerm(Constants.pathGlob)

        #expect(term.isGlob)
        #expect(term.matches(name: Constants.log, relativePath: Constants.stacksLog, isDirectory: false))
        #expect(!term.matches(name: Constants.log, relativePath: Constants.otherLog, isDirectory: false))
        #expect(!term.matches(name: Constants.stacks, relativePath: Constants.stacks, isDirectory: true))
        #expect(SearchTerm("*.log").matches(name: Constants.log, relativePath: Constants.stacksLog, isDirectory: false))
        #expect(!SearchTerm(TestSearch.rankTerm).isGlob)
    }

    @Test("A name is closest whole, then by its start, then anywhere; every name a shape fits is equal")
    func namesAreRankedByHowCloseTheyAre() {
        let term = SearchTerm(TestSearch.rankTerm)

        #expect(term.rank("Rapport") == 0)
        #expect(term.rank(TestSearch.rankPrefixFile) == 1)
        #expect(term.rank(TestSearch.rankContainsFile) == 2)
        #expect(SearchTerm(TestSearch.pdfGlob).rank(TestSearch.rankContainsFile) == 0)
    }

    @Test("Results are ordered as the server orders them: names closest and shortest first, then contents by path")
    func resultsAreOrderedLikeTheServer() {
        let annex = SearchResultItem(
            name: "vieux-rapport-2019-annexe.pdf",
            path: "",
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let pdf = SearchResultItem(
            name: TestSearch.rankPrefixFile,
            path: TestFolder.docs,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let folder = SearchResultItem(
            name: TestSearch.rankPrefixFolder,
            path: "",
            kind: SearchResultItem.directoryKind,
            isNameMatch: true
        )
        let exact = SearchResultItem(name: TestSearch.rankTerm, path: Constants.z, kind: SearchResultItem.fileKind)
        let copy = SearchResultItem(
            name: TestSearch.rankPrefixFile,
            path: Constants.archive,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let notes = SearchResultItem(
            name: "notes.txt",
            path: TestFolder.docs,
            kind: SearchResultItem.fileKind,
            matchLine: TestSearch.rankTerm,
            matchLineNumber: 2,
            isNameMatch: false,
            isContentMatch: true
        )
        let memo = SearchResultItem(
            name: "memo.txt",
            path: "A",
            kind: SearchResultItem.fileKind,
            isNameMatch: false,
            isContentMatch: true
        )

        let ranked = SearchTerm(TestSearch.rankTerm).ranked([notes, annex, pdf, memo, folder, exact, copy])

        #expect(ranked.map(\.id) == [
            "Z/rapport",
            "Rapports",
            "Archive/rapport.pdf",
            "Docs/rapport.pdf",
            "vieux-rapport-2019-annexe.pdf",
            "A/memo.txt",
            "Docs/notes.txt",
        ])
    }
}
