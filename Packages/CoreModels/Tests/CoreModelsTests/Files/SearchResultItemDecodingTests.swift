@testable import CoreModels
import Foundation
import Testing

@Suite("SearchResultItem decoding")
struct SearchResultItemDecodingTests {
    @Test("happy path: a filename match decodes without match line fields")
    func decodesFilenameMatch() throws {
        let item = try CoreModelsFixture.searchResultItemFilenameMatch.decode(SearchResultItem.self)
        #expect(item.matchLine == nil)
        #expect(item.matchLineNumber == nil)
        #expect(item.isDirectory == false)
    }

    @Test("happy path: a content match includes the matching line and its number")
    func decodesContentMatch() throws {
        let item = try CoreModelsFixture.searchResultItemContentMatch.decode(SearchResultItem.self)
        #expect(item.matchLine == "TODO: fix this")
        #expect(item.matchLineNumber == 42)
    }

    @Test("edge case: kind \"dir\" marks the result as a directory")
    func dirKindIsDirectory() throws {
        let item = try CoreModelsFixture.searchResultItemDirectoryKind.decode(SearchResultItem.self)
        #expect(item.isDirectory == true)
    }

    @Test("edge case: id is just the name when path is empty")
    func idIsNameWhenPathEmpty() {
        let item = SearchResultItem(name: "Volume", path: "", kind: "dir")
        #expect(item.id == "Volume")
    }
}
