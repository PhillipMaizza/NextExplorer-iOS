import Foundation
import Testing
@testable import CoreModels

@Suite("SearchResultItem decoding")
struct SearchResultItemDecodingTests {
    @Test("happy path: a filename match decodes without match line fields")
    func decodesFilenameMatch() throws {
        let json = #"{"name": "report.pdf", "path": "Home/Docs", "kind": "pdf"}"#
        let item = try JSONDecoder().decode(SearchResultItem.self, from: Data(json.utf8))
        #expect(item.matchLine == nil)
        #expect(item.matchLineNumber == nil)
        #expect(item.isDirectory == false)
    }

    @Test("happy path: a content match includes the matching line and its number")
    func decodesContentMatch() throws {
        let json = #"{"name": "notes.txt", "path": "Home", "kind": "txt", "matchLine": "TODO: fix this", "matchLineNumber": 42}"#
        let item = try JSONDecoder().decode(SearchResultItem.self, from: Data(json.utf8))
        #expect(item.matchLine == "TODO: fix this")
        #expect(item.matchLineNumber == 42)
    }

    @Test("edge case: kind \"dir\" marks the result as a directory")
    func dirKindIsDirectory() throws {
        let json = #"{"name": "Docs", "path": "Home", "kind": "dir"}"#
        let item = try JSONDecoder().decode(SearchResultItem.self, from: Data(json.utf8))
        #expect(item.isDirectory == true)
    }

    @Test("edge case: id is just the name when path is empty")
    func idIsNameWhenPathEmpty() {
        let item = SearchResultItem(name: "Volume", path: "", kind: "dir")
        #expect(item.id == "Volume")
    }

    @Test("error path: missing required field fails to decode")
    func missingRequiredFieldThrows() {
        let json = #"{"name": "notes.txt"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(SearchResultItem.self, from: Data(json.utf8))
        }
    }
}
