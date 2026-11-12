import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// File and folder mutations (create, rename, delete, transfer, compress, extract) and metadata through `FilesClient.live` against a stubbed `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite
    struct FilesClientItemMutationTests: FilesClientLiveHarness {
        @Test
        func createFilePostsTheParentAndNameAndDecodesTheItem() async throws {
            let body = try FilesClientFixture.itemMutationCreatedNotesTxt.data()
            stub(statusCode: 201, body: body)

            let item = try await makeClient().createFile(serverURL, "Docs", "notes.txt")

            #expect(item.name == "notes.txt")
            #expect(item.path == "Docs")
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/files/file")
            let sent = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(JSONSerialization.jsonObject(with: sent) as? [String: String])
            #expect(json == ["path": "Docs", "name": "notes.txt"])
        }

        @Test
        func renameItemSendsTheParentPathOriginalNameAndNewNameAndDecodesTheRenamedItem() async throws {
            let renameJSON = try FilesClientFixture.itemMutationRenameVacation.data()
            stub(statusCode: 200, body: renameJSON)
            StubURLProtocol.capturedRequest = nil
            let item = FileItem(name: "vacation.jpg", path: "Photos", dateModified: MockDate.date, size: 1024, kind: "jpg")
            let renamed = try await makeClient().renameItem(serverURL, item, "vacation-2024.jpg")
            #expect(renamed.name == "vacation-2024.jpg")
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["path"] == "Photos")
            #expect(json["name"] == "vacation.jpg")
            #expect(json["newName"] == "vacation-2024.jpg")
        }

        @Test
        func renameItemMapsAConflictingNameToAServerError() async throws {
            stub(statusCode: 409, body: Data())
            let item = FileItem(name: "vacation.jpg", path: "Photos", dateModified: MockDate.date, size: 0, kind: "jpg")
            await #expect(throws: FilesClientError.server(statusCode: 409)) {
                _ = try await makeClient().renameItem(serverURL, item, "taken.jpg")
            }
        }

        @Test
        func deleteItemsSendsPathNameAndKindForEveryItem() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.commonSuccessNoItems.data())
            StubURLProtocol.capturedRequest = nil
            let first = FileItem(name: "a.txt", path: "Docs", dateModified: MockDate.date, size: 0, kind: "txt")
            let second = FileItem(name: "Photos", path: "", dateModified: MockDate.date, size: 0, kind: "directory")
            try await makeClient().deleteItems(serverURL, [first, second])
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "DELETE")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [[String: String]]])
            let items = try #require(json["items"])
            #expect(items.count == 2)
            #expect(items[0]["name"] == "a.txt")
            #expect(items[1]["kind"] == "directory")
        }

        @Test
        func deleteItemsMapsAForbiddenResponseToAServerError() async throws {
            stub(statusCode: 403, body: Data())
            let item = FileItem(name: "readonly.txt", path: "", dateModified: MockDate.date, size: 0, kind: "txt")
            await #expect(throws: FilesClientError.forbidden(message: nil)) {
                try await makeClient().deleteItems(serverURL, [item])
            }
        }

        @Test
        func deleteItemsWithAnEmptyArrayStillSendsTheRequest() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.commonSuccessNoItems.data())
            StubURLProtocol.capturedRequest = nil
            try await makeClient().deleteItems(serverURL, [])
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [[String: String]]])
            #expect(json["items"]?.isEmpty == true)
        }

        @Test
        func transferItemsCopyPostsToCopyEndpointWithItemsAndDestination() async throws {
            let json = try FilesClientFixture.itemMutationTransferCopyToDocuments.data()
            stub(statusCode: 200, body: json)
            StubURLProtocol.capturedRequest = nil
            let item = FileItem(name: "a.txt", path: "Inbox", dateModified: MockDate.date, size: 0, kind: "txt")
            let result = try await makeClient().transferItems(serverURL, [item], "Documents", .copy)
            #expect(result.destination == "Documents")
            #expect(result.movedCount == 1)
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/files/copy")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["destination"] as? String == "Documents")
            let items = try #require(object["items"] as? [[String: String]])
            #expect(items.first?["path"] == "Inbox")
            #expect(items.first?["name"] == "a.txt")
        }

        @Test
        func transferItemsMovePostsToMoveEndpoint() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.itemMutationTransferToArchive.data())
            StubURLProtocol.capturedRequest = nil
            let item = FileItem(name: "old", path: "", dateModified: MockDate.date, size: 0, kind: "directory")
            _ = try await makeClient().transferItems(serverURL, [item], "Archive", .move)
            #expect(StubURLProtocol.capturedRequest?.url?.path == "/api/files/move")
        }

        @Test
        func transferItemsSurfacesAValidationMessageFromTheServer() async throws {
            stub(
                statusCode: 500,
                body: try FilesClientFixture.itemMutationErrorTransferToRoot.data()
            )
            let item = FileItem(name: "a.txt", path: "Inbox", dateModified: MockDate.date, size: 0, kind: "txt")
            await #expect(throws: FilesClientError.serverMessage(statusCode: 500, message: "Cannot copy or move items to the root path.")) {
                _ = try await makeClient().transferItems(serverURL, [item], "", .move)
            }
        }

        @Test
        func transferItemsMapsA401ToSessionExpired() async throws {
            stub(statusCode: 401, body: Data())
            let item = FileItem(name: "a.txt", path: "Inbox", dateModified: MockDate.date, size: 0, kind: "txt")
            await #expect(throws: FilesClientError.sessionExpired) {
                _ = try await makeClient().transferItems(serverURL, [item], "Documents", .copy)
            }
        }

        @Test
        func fetchMetadataDecodesAPlainFileWithNoNestedMetadata() async throws {
            let json = try FilesClientFixture.metadataPlainFile.data()
            stub(statusCode: 200, body: json)
            let metadata = try await makeClient().fetchMetadata(serverURL, "Docs/notes.txt")
            #expect(metadata.name == "notes.txt")
            #expect(metadata.image == nil)
        }

        @Test
        func fetchMetadataDecodesADirectorySummary() async throws {
            let json = try FilesClientFixture.metadataDirectorySummary.data()
            stub(statusCode: 200, body: json)
            let metadata = try await makeClient().fetchMetadata(serverURL, "Photos")
            #expect(metadata.directory?.fileCount == 42)
        }

        @Test
        func fetchMetadataPercentEncodesEachPathSegment() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.metadataHashTagDirectory.data())
            StubURLProtocol.capturedRequest = nil
            _ = try await makeClient().fetchMetadata(serverURL, "My Docs/#tag")
            let url = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(url.pathComponents.contains("#tag"))
        }

        @Test
        func fetchMetadataMapsForbiddenToAServerError() async throws {
            stub(statusCode: 403, body: Data())
            await #expect(throws: FilesClientError.forbidden(message: nil)) {
                _ = try await makeClient().fetchMetadata(serverURL, "Private")
            }
        }

        @Test
        func extractZipHitsPlainAPIExtractPathNotAPIFilesExtract() async throws {
            // Regression coverage for a real bug this session: the endpoint is
            // `POST /api/files/zip/extract` (zip.js's own route path, mounted at plain `/api`):
            // easy to get subtly wrong the same way `downloadRawFile` originally was.
            let json = try FilesClientFixture.itemMutationCompressedBundleDirectory.string()
            stub(statusCode: 201, body: json.data(using: .utf8)!)
            StubURLProtocol.capturedRequest = nil
            let item = FileItem(name: "bundle.zip", path: "", dateModified: MockDate.date, size: 0, kind: "zip")

            let extracted = try await makeClient().extractZip(serverURL, item)

            #expect(extracted.name == "bundle")
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/files/zip/extract")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let bodyJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(bodyJSON["path"] == "bundle.zip")
        }

        @Test
        func extractZipMapsUnsupportedFormatToAServerError() async throws {
            stub(statusCode: 415, body: Data())
            let item = FileItem(name: "bundle.rar", path: "", dateModified: MockDate.date, size: 0, kind: "rar")
            await #expect(throws: FilesClientError.server(statusCode: 415)) {
                _ = try await makeClient().extractZip(serverURL, item)
            }
        }

        @Test
        func compressItemSendsItemsAndDestinationAndDecodesTheNewArchive() async throws {
            let json = try FilesClientFixture.itemMutationCompressedDocumentsZip.string()
            stub(statusCode: 201, body: json.data(using: .utf8)!)
            StubURLProtocol.capturedRequest = nil
            let item = FileItem(name: "Documents", path: "", dateModified: MockDate.date, size: 0, kind: "directory")

            let compressed = try await makeClient().compressItem(serverURL, item)

            #expect(compressed.name == "Documents.zip")
            let request = try #require(StubURLProtocol.capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/files/zip/compress")
            let body = try #require(StubURLProtocol.capturedRequestBody)
            let bodyJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(bodyJSON["destination"] as? String == "")
            let items = try #require(bodyJSON["items"] as? [[String: String]])
            #expect(items == [["name": "Documents", "path": ""]])
        }

        @Test
        func compressItemMapsReadOnlyDestinationToAServerError() async throws {
            stub(statusCode: 403, body: Data())
            let item = FileItem(name: "Documents", path: "", dateModified: MockDate.date, size: 0, kind: "directory")
            await #expect(throws: FilesClientError.forbidden(message: nil)) {
                _ = try await makeClient().compressItem(serverURL, item)
            }
        }

        @Test
        func compressItemDecodesTheDoneLineOfAnNDJSONProgressStream() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.itemMutationNdjsonCompressDone.data(), headers: ["Content-Type": "application/x-ndjson; charset=utf-8"])
            let item = FileItem(name: "Documents", path: "", dateModified: MockDate.date, size: 0, kind: "directory")

            let compressed = try await makeClient().compressItem(serverURL, item)

            #expect(compressed.name == "Documents.zip")
            #expect(compressed.size == 157)
        }

        @Test
        func compressItemSurfacesTheErrorLineOfAnNDJSONStream() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.itemMutationNdjsonCompressError.data(), headers: ["Content-Type": "application/x-ndjson"])
            let item = FileItem(name: "Documents", path: "", dateModified: MockDate.date, size: 0, kind: "directory")
            await #expect(throws: FilesClientError.serverMessage(statusCode: 500, message: "Disk full")) {
                _ = try await makeClient().compressItem(serverURL, item)
            }
        }

        @Test
        func extractZipDecodesTheDoneLineOfAnNDJSONProgressStream() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.itemMutationNdjsonExtractDone.data(), headers: ["Content-Type": "application/x-ndjson"])
            let archive = FileItem(name: "photos.zip", path: "Files", dateModified: MockDate.date, size: 10, kind: "zip")

            let extracted = try await makeClient().extractZip(serverURL, archive)

            #expect(extracted.name == "photos")
            #expect(extracted.isDirectory)
        }

        @Test
        func anNDJSONStreamWithoutADoneLineIsADecodingError() throws {
            let data = try FilesClientFixture.itemMutationArchiveStartLine.data()
            #expect(throws: FilesClientError.self) {
                _ = try FilesService.decodeArchiveOperation(FilesService.CompressItemEnvelope.self, from: data)
            }
        }
    }
}
