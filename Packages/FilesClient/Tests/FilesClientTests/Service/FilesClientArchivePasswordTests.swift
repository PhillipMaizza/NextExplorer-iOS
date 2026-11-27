import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

extension FilesClientLiveTests {
    struct FilesClientArchivePasswordTests: FilesClientLiveHarness {
        @Test(arguments: [
            (FilesClientFixture.itemMutationNdjsonExtractPasswordRequired, FilesClientError.archivePasswordRequired),
            (FilesClientFixture.itemMutationNdjsonExtractPasswordInvalid, FilesClientError.archiveInvalidPassword),
        ])
        func extractZipMapsThePasswordCodesAndSendsThePassword(
            fixture: FilesClientFixture,
            expected: FilesClientError
        ) async throws {
            try stub(
                statusCode: 200,
                body: fixture.data(),
                headers: [HTTPHeaderField.contentType: "application/x-ndjson"]
            )
            let archive = FileItem(
                name: "photos.zip",
                path: TestFolder.files,
                dateModified: MockDate.date,
                size: 10,
                kind: "zip"
            )

            await #expect(throws: expected) {
                _ = try await makeClient().extractZipHere(serverURL, archive, Constants.password)
            }
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let bodyJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(bodyJSON["password"] == Constants.password)
        }
    }
}

private enum Constants {
    static let password = "open sesame"
}
