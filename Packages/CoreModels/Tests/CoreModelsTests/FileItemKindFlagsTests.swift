@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("FileItem kind flags and fingerprints")
struct FileItemKindFlagsTests {
    private func item(kind: String, dateModified: Date = MockDate.date, size: Int64 = 0) -> FileItem {
        FileItem(name: "n", path: TestFolder.docs, dateModified: dateModified, size: size, kind: kind)
    }

    private struct Case: Sendable {
        let kind: String
        let isSVG: Bool
        let isPDF: Bool
        let isHTML: Bool
        let isGoogleDocsPointer: Bool
    }

    private static let cases = [
        Case(kind: "svg", isSVG: true, isPDF: false, isHTML: false, isGoogleDocsPointer: false),
        Case(kind: "SVG", isSVG: true, isPDF: false, isHTML: false, isGoogleDocsPointer: false),
        Case(kind: "pdf", isSVG: false, isPDF: true, isHTML: false, isGoogleDocsPointer: false),
        Case(kind: "PDF", isSVG: false, isPDF: true, isHTML: false, isGoogleDocsPointer: false),
        Case(kind: "html", isSVG: false, isPDF: false, isHTML: true, isGoogleDocsPointer: false),
        Case(kind: "HTM", isSVG: false, isPDF: false, isHTML: true, isGoogleDocsPointer: false),
        Case(kind: "gsheet", isSVG: false, isPDF: false, isHTML: false, isGoogleDocsPointer: true),
        Case(kind: "GDOC", isSVG: false, isPDF: false, isHTML: false, isGoogleDocsPointer: true),
        Case(kind: TestKind.text, isSVG: false, isPDF: false, isHTML: false, isGoogleDocsPointer: false),
        Case(kind: FileItem.directoryKind, isSVG: false, isPDF: false, isHTML: false, isGoogleDocsPointer: false),
        Case(kind: "", isSVG: false, isPDF: false, isHTML: false, isGoogleDocsPointer: false),
        Case(kind: "htmlx", isSVG: false, isPDF: false, isHTML: false, isGoogleDocsPointer: false),
    ]

    @Test("the SVG, PDF, HTML and Drive pointer flags match the lowercased kind exactly", arguments: cases)
    private func flagsFollowKind(_ testCase: Case) {
        let value = item(kind: testCase.kind)
        #expect(value.isSVG == testCase.isSVG)
        #expect(value.isPDF == testCase.isPDF)
        #expect(value.isHTML == testCase.isHTML)
        #expect(value.isGoogleDocsPointer == testCase.isGoogleDocsPointer)
    }

    @Test("an item with the placeholder date is not dated and any real date is")
    func knownDate() {
        #expect(!item(kind: TestKind.text, dateModified: FileItem.unknownDate).hasKnownDate)
        #expect(item(kind: TestKind.text, dateModified: MockDate.date).hasKnownDate)
        #expect(item(kind: TestKind.text, dateModified: .distantFuture).hasKnownDate)
    }

    @Test("the cache signature joins the modified time and the byte size")
    func cacheSignatureValue() {
        #expect(item(kind: TestKind.text, size: 42).cacheSignature == "1700000000.0|42")
        #expect(item(kind: TestKind.text, dateModified: MockDate.date.addingTimeInterval(0.5), size: 0)
            .cacheSignature == "1700000000.5|0")
    }
}
