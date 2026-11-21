@testable import CoreModels
import Foundation
import Testing
import TestUtils

struct GoogleDocsPointerTests {
    @Test func recognisesTheDriveStubExtensions() {
        #expect(GoogleDocsPointer.isPointerKind("gsheet"))
        #expect(GoogleDocsPointer.isPointerKind("GDOC"))
        #expect(GoogleDocsPointer.isPointerKind("gslides"))
        #expect(!GoogleDocsPointer.isPointerKind("txt"))
        #expect(!GoogleDocsPointer.isPointerKind("xlsx"))
    }

    @Test func pullsTheHTTPSLinkOutOfAStub() throws {
        let stub = try CoreModelsFixture.googleDocsPointerDriveStub.string()
        #expect(GoogleDocsPointer.targetURL(fromContents: stub)?
            .absoluteString == "https://docs.google.com/spreadsheets/d/ABC123/edit")
    }

    @Test func rejectsJunkAndNonHTTPLinks() throws {
        let junk = try CoreModelsFixture.googleDocsPointerNotJson.string()
        let withoutURL = try CoreModelsFixture.googleDocsPointerMissingUrl.string()
        let nonHTTPLink = try CoreModelsFixture.googleDocsPointerNonHttpLink.string()
        #expect(GoogleDocsPointer.targetURL(fromContents: junk) == nil)
        #expect(GoogleDocsPointer.targetURL(fromContents: withoutURL) == nil)
        #expect(GoogleDocsPointer.targetURL(fromContents: nonHTTPLink) == nil)
    }

    @Test("security: a stub opens Google over https only, so a shared file cannot send the user to a lookalike page")
    func opensOnlyGoogleOverHTTPS() throws {
        let drive = try CoreModelsFixture.googleDocsPointerDriveHost.string()
        let lookalike = try CoreModelsFixture.googleDocsPointerLookalikeHost.string()
        let plainHTTP = try CoreModelsFixture.googleDocsPointerPlainHttp.string()
        #expect(GoogleDocsPointer.targetURL(fromContents: drive)?.host() == "drive.google.com")
        #expect(GoogleDocsPointer.targetURL(fromContents: lookalike) == nil)
        #expect(GoogleDocsPointer.targetURL(fromContents: plainHTTP) == nil)
    }
}
