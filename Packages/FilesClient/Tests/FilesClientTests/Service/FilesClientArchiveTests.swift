import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

extension FilesClientLiveTests {
    struct FilesClientArchiveTests: FilesClientLiveHarness {
        private enum Constants {
            static let awkwardFolder = "a+b & c#d"
            static let encodedAwkwardFolder = "a%2Bb%20%26%20c%23d"
        }

        private var archive: FileItem {
            FileItem(name: TestFile.archive, path: TestFolder.files, dateModified: MockDate.date, size: 0, kind: "zip")
        }

        @Test
        func listArchiveAsksForOneLevelAndDecodesFoldersFilesAndLocks() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.archiveListRoot.data())
            StubURLProtocol.capturedRequest = nil

            let listing = try await makeClient().listArchive(serverURL, archive, "")

            #expect(listing.entries.map(\.name) == [TestFolder.photos, TestFile.notes, TestFile.photo])
            #expect(listing.entries[0].isDirectory)
            #expect(listing.entries[0].size == nil)
            #expect(listing.entries[1].isEncrypted)
            #expect(listing.entries[2].size == 10264)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.get.rawValue)
            #expect(request.url?.path == "/api/archive/list")
        }

        @Test
        func listArchiveEncodesReservedCharactersInThePosition() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.archiveListRoot.data())
            StubURLProtocol.capturedRequest = nil

            _ = try await makeClient().listArchive(serverURL, archive, Constants.awkwardFolder)

            let query = try #require(StubURLProtocol.capturedRequest?.url?.query(percentEncoded: true))
            #expect(query.contains("inside=\(Constants.encodedAwkwardFolder)"))
            #expect(query.contains("path=\(TestFolder.files)%2F\(TestFile.archive)"))
        }

        @Test
        func listArchiveKeepsTheStatusOfAPasswordProtectedArchive() async throws {
            stub(statusCode: HTTPStatus.conflict.rawValue, body: Data())

            await #expect(throws: FilesClientError.server(statusCode: HTTPStatus.conflict.rawValue)) {
                _ = try await makeClient().listArchive(serverURL, archive, "")
            }
        }

        @Test
        func downloadArchiveEntryFetchesOnlyThatEntry() async throws {
            stub(statusCode: 200, body: Data(TestFile.notes.utf8))
            StubURLProtocol.capturedRequest = nil

            let url = try await makeClient().downloadArchiveEntry(
                serverURL,
                archive,
                "\(TestFolder.photos)/\(TestFile.photo)"
            )
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(try String(contentsOf: url, encoding: .utf8) == TestFile.notes)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.get.rawValue)
            #expect(request.url?.path == "/api/archive/entry")
            #expect(request.url?.query(percentEncoded: true)?
                .contains("entry=\(TestFolder.photos)%2F\(TestFile.photo)") == true)
        }

        @Test
        func extractArchiveEntriesPostsTheChosenEntriesAndReturnsWhatLanded() async throws {
            try stub(
                statusCode: 200,
                body: FilesClientFixture.archiveExtractDone.data(),
                headers: [HTTPHeaderField.contentType: "application/x-ndjson; charset=utf-8"]
            )
            StubURLProtocol.capturedRequest = nil

            let items = try await makeClient().extractArchiveEntries(serverURL, archive, [TestFile.photo])

            #expect(items.map(\.name) == [TestFile.photo])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == HTTPMethod.post.rawValue)
            #expect(request.url?.path == "/api/archive/extract")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["path"] as? String == archive.id)
            #expect(json["entries"] as? [String] == [TestFile.photo])
        }
    }
}
