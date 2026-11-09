@testable import CoreModels
import Foundation
import Testing

struct GoogleDocsPointerTests {
    @Test func recognisesTheDriveStubExtensions() {
        #expect(GoogleDocsPointer.isPointerKind("gsheet"))
        #expect(GoogleDocsPointer.isPointerKind("GDOC"))
        #expect(GoogleDocsPointer.isPointerKind("gslides"))
        #expect(!GoogleDocsPointer.isPointerKind("txt"))
        #expect(!GoogleDocsPointer.isPointerKind("xlsx"))
    }

    @Test func pullsTheHTTPSLinkOutOfAStub() {
        let stub = #"{"url": "https://docs.google.com/spreadsheets/d/ABC123/edit", "resource_id": "spreadsheet:ABC123", "email": "a@b.com"}"#
        #expect(GoogleDocsPointer.targetURL(fromContents: stub)?.absoluteString == "https://docs.google.com/spreadsheets/d/ABC123/edit")
    }

    @Test func rejectsJunkAndNonHTTPLinks() {
        #expect(GoogleDocsPointer.targetURL(fromContents: "not json") == nil)
        #expect(GoogleDocsPointer.targetURL(fromContents: #"{"resource_id": "x"}"#) == nil)
        #expect(GoogleDocsPointer.targetURL(fromContents: #"{"url": "file:///etc/passwd"}"#) == nil)
    }
}
