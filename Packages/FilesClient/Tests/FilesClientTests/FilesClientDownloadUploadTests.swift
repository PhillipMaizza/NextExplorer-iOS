import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Raw download, item download and multipart upload through `FilesClient.live` against a stubbed `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite
    struct FilesClientDownloadUploadTests: FilesClientLiveHarness {
        func makeTempFile(_ name: String, contents: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(TestID.name())-\(name)")
            try Data(contents.utf8).write(to: url)
            return url
        }

        @Test
        func downloadRawFileHitsPlainAPIDownloadNotAPIFilesDownload() async throws {
            // Regression coverage: this endpoint's real path is `POST /api/download`; the
            // backend file lives at `routes/files/download.js` but is mounted at plain `/api` in
            // `routes/index.js`, not `/api/files`. Got this wrong once already (silent 404s on
            // every zip/rar/doc/docx preview until caught by live testing, not this test suite).
            stub(statusCode: 200, body: Data("raw file bytes".utf8))
            StubURLProtocol.capturedRequest = nil
            let item = FileItem(name: FilesClientTestValue.bundleName, path: "Archives", dateModified: MockDate.date, size: 0, kind: "zip")

            _ = try await makeClient().downloadRawFile(serverURL, item)

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/download")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let bodyJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(bodyJSON["path"] == "Archives/bundle.zip")
        }

        @Test
        func downloadRawFileMapsAccessDeniedToAServerError() async throws {
            stub(statusCode: 403, body: Data())
            let item = FileItem(name: "secret.docx", path: "", dateModified: MockDate.date, size: 0, kind: "docx")
            await #expect(throws: FilesClientError.forbidden(message: nil)) {
                _ = try await makeClient().downloadRawFile(serverURL, item)
            }
        }

        @Test
        func downloadItemPostsTheFolderPathAndReturnsAFileTheCallerOwns() async throws {
            stub(statusCode: 200, body: Data(Constants.zipBytes.utf8), headers: [HTTPHeaderField.contentType: "application/zip"])
            StubURLProtocol.capturedRequest = nil
            let folder = FileItem(name: TestFolder.photos, path: TestFolder.files, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)

            let url = try await makeClient().downloadItem(serverURL, folder) { _ in }
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(try Data(contentsOf: url) == Data(Constants.zipBytes.utf8))
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/download")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let bodyJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(bodyJSON == ["path": "Files/Photos"])
        }

        @Test
        func downloadItemMapsAServerErrorAndLeavesNoFileBehind() async throws {
            stub(statusCode: 500, body: Data())
            let item = FileItem(name: "movie.mkv", path: TestFolder.files, dateModified: MockDate.date, size: 0, kind: "mkv")
            await #expect(throws: FilesClientError.server(statusCode: 500)) {
                _ = try await makeClient().downloadItem(serverURL, item) { _ in }
            }
        }

        @Test
        func uploadFilePostsAMultipartEnvelopeToTheUploadEndpointAndDecodesTheStoredFile() async throws {
            let responseJSON = try FilesClientFixture.uploadRenamedNotesCopy.string()
            stub(statusCode: 200, body: Data(responseJSON.utf8))
            StubURLProtocol.capturedRequest = nil
            let fileURL = try makeTempFile(TestFile.notes, contents: Constants.uploadBody)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let stored = try await makeClient().uploadFile(serverURL, fileURL, TestFile.notes, TestFolder.inbox) { _ in }

            #expect(stored.name == "notes (1).txt")
            #expect(stored.path == TestFolder.inbox)

            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/upload")
            let contentType = try #require(request.value(forHTTPHeaderField: HTTPHeaderField.contentType))
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))

            let body = try #require(StubURLProtocol.capturedRequestBody)
            let bodyString = try #require(String(data: body, encoding: .utf8))
            // Text fields must precede the file part, and the file bytes are included verbatim.
            let uploadToRange = try #require(bodyString.range(of: "name=\"uploadTo\""))
            let fileDataRange = try #require(bodyString.range(of: "name=\"filedata\"; filename=\"notes.txt\""))
            #expect(uploadToRange.lowerBound < fileDataRange.lowerBound)
            #expect(bodyString.contains("\r\n\r\nInbox\r\n"))
            #expect(bodyString.contains("\r\n\r\nnotes.txt\r\n"))
            #expect(bodyString.contains(Constants.uploadBody))
        }

        @Test
        func uploadFileSanitizesQuotesAndNewlinesOutOfTheHeaderFilename() async throws {
            let responseJSON = try FilesClientFixture.uploadRenamedWeirdName.string()
            stub(statusCode: 200, body: Data(responseJSON.utf8))
            StubURLProtocol.capturedRequest = nil
            let fileURL = try makeTempFile("weird.txt", contents: "x")
            defer { try? FileManager.default.removeItem(at: fileURL) }

            _ = try await makeClient().uploadFile(serverURL, fileURL, "we\"ir\nd.txt", TestFolder.inbox) { _ in }

            let body = try #require(StubURLProtocol.capturedRequestBody)
            let bodyString = try #require(String(data: body, encoding: .utf8))
            #expect(bodyString.contains("filename=\"we'ir d.txt\""))
            // The `relativePath` field keeps the quote for the server but never carries a line break.
            #expect(bodyString.contains("name=\"relativePath\"\r\n\r\nwe\"ir d.txt\r\n"))
        }

        @Test
        func uploadFileSurfacesTheServerMessageOnRejection() async throws {
            let errorJSON = try FilesClientFixture.uploadErrorForbidden.string()
            stub(statusCode: 403, body: Data(errorJSON.utf8))
            let fileURL = try makeTempFile(TestFile.notes, contents: "x")
            defer { try? FileManager.default.removeItem(at: fileURL) }

            await #expect(throws: FilesClientError.forbidden(message: "Cannot upload files to this path.")) {
                _ = try await makeClient().uploadFile(serverURL, fileURL, TestFile.notes, TestFolder.inbox) { _ in }
            }
        }
    }
}

private enum Constants {
    static let uploadBody = "hello upload"
    static let zipBytes = "PK-zip-bytes"
}
