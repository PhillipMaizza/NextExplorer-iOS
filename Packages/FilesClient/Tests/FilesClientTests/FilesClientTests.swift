import CoreModels
import Foundation
import NetworkClient
import Testing

@testable import FilesClient

@Suite
struct FilesClientTests {
    @Test
    func previewValueBrowseReturnsSeededItems() async throws {
        let result = try await FilesClient.previewValue.browse(URL(string: "https://example.com")!, "")
        #expect(!result.items.isEmpty)
    }
}

// MARK: - Live wire-format / error-mapping tests

/// Exercises `FilesService` through `FilesClient.live` against a stubbed `URLSession`, so
/// HTTP status mapping and JSON decoding are verified against a real `NetworkClient`, not
/// just the reducer-level `Result` cases the feature tests assume.
@Suite(.serialized)
struct FilesClientLiveTests {
    private let serverURL = URL(string: "https://example.com")!

    private func makeClient() -> FilesClient {
        .live(networkClient: .live(protocolClasses: [StubURLProtocol.self]))
    }

    private func stub(statusCode: Int, body: Data) {
        StubURLProtocol.failure = nil
        StubURLProtocol.stub = .init(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: body)
    }

    private let browseResultJSON = """
    {
        "items": [
            {
                "name": "Docs",
                "path": "",
                "dateModified": "2024-01-01T00:00:00.000Z",
                "size": 0,
                "kind": "directory",
                "supportsThumbnail": false
            }
        ],
        "access": {
            "canRead": true, "canWrite": false, "canUpload": false,
            "canDelete": false, "canShare": false, "canDownload": true
        },
        "path": ""
    }
    """.data(using: .utf8)!

    // MARK: Happy path

    @Test
    func browseDecodesASuccessfulResponse() async throws {
        stub(statusCode: 200, body: browseResultJSON)
        let result = try await makeClient().browse(serverURL, "")
        #expect(result.items.map(\.name) == ["Docs"])
        #expect(result.access.canRead == true)
    }

    @Test
    func browseDecodesFractionalSecondISO8601Dates() async throws {
        stub(statusCode: 200, body: browseResultJSON)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let result = try await makeClient().browse(serverURL, "")
        #expect(result.items.first?.dateModified == formatter.date(from: "2024-01-01T00:00:00.000Z"))
    }

    @Test
    func fetchPreferencesFallsBackToDefaultsWhenUserKeyIsMissing() async throws {
        stub(statusCode: 200, body: #"{"branding": {}}"#.data(using: .utf8)!)
        let preferences = try await makeClient().fetchPreferences(serverURL)
        #expect(preferences == UserPreferences())
    }

    @Test
    func fetchPreferencesFallsBackPerFieldWhenOnlyOneKeyIsPresent() async throws {
        stub(statusCode: 200, body: #"{"user": {"showHiddenFiles": true}}"#.data(using: .utf8)!)
        let preferences = try await makeClient().fetchPreferences(serverURL)
        #expect(preferences == UserPreferences(showHiddenFiles: true, showThumbnails: true))
    }

    // MARK: Error path — HTTP status mapping

    @Test
    func browseMaps401ToSessionExpired() async throws {
        stub(statusCode: 401, body: Data())
        await #expect(throws: FilesClientError.sessionExpired) {
            _ = try await makeClient().browse(serverURL, "")
        }
    }

    @Test
    func browseMaps429ToRateLimited() async throws {
        stub(statusCode: 429, body: Data())
        await #expect(throws: FilesClientError.rateLimited) {
            _ = try await makeClient().browse(serverURL, "")
        }
    }

    @Test
    func browseMaps500ToServerErrorWithStatusCode() async throws {
        stub(statusCode: 500, body: Data())
        await #expect(throws: FilesClientError.server(statusCode: 500)) {
            _ = try await makeClient().browse(serverURL, "")
        }
    }

    @Test
    func browseMapsMalformedJSONToADecodingError() async throws {
        stub(statusCode: 200, body: "not json".data(using: .utf8)!)
        await #expect(throws: FilesClientError.self) {
            _ = try await makeClient().browse(serverURL, "")
        }
    }

    @Test
    func browseMapsTransportFailureToANetworkError() async throws {
        StubURLProtocol.stub = nil
        StubURLProtocol.failure = URLError(.notConnectedToInternet)
        await #expect(throws: FilesClientError.self) {
            _ = try await makeClient().browse(serverURL, "")
        }
    }

    // MARK: Edge cases — request construction

    @Test
    func browsePercentEncodesPathSegmentsWithSpecialCharacters() async throws {
        stub(statusCode: 200, body: browseResultJSON)
        StubURLProtocol.capturedRequest = nil
        _ = try await makeClient().browse(serverURL, "My Docs/#tag/日本語")
        let url = try #require(StubURLProtocol.capturedRequest?.url)
        #expect(url.path.contains("My%20Docs") || url.path.contains("My Docs"))
        #expect(url.pathComponents.contains("#tag"))
        #expect(url.pathComponents.contains("日本語"))
    }

    @Test
    func browseOfAnEmptyPathHitsTheRootBrowseEndpointWithATrailingSlash() async throws {
        stub(statusCode: 200, body: browseResultJSON)
        StubURLProtocol.capturedRequest = nil
        _ = try await makeClient().browse(serverURL, "")
        let url = try #require(StubURLProtocol.capturedRequest?.url)
        #expect(url.absoluteString.hasSuffix("/api/browse/"))
    }

    @Test
    func searchOmitsPathAndLimitQueryItemsWhenNotProvided() async throws {
        stub(statusCode: 200, body: #"{"items": []}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        _ = try await makeClient().search(serverURL, "", "vacation", nil)
        let url = try #require(StubURLProtocol.capturedRequest?.url)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems.contains(URLQueryItem(name: "q", value: "vacation")))
        #expect(!queryItems.contains { $0.name == "path" })
        #expect(!queryItems.contains { $0.name == "limit" })
    }

    @Test
    func searchIncludesPathAndLimitWhenProvided() async throws {
        stub(statusCode: 200, body: #"{"items": []}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        _ = try await makeClient().search(serverURL, "Photos", "vacation", 50)
        let url = try #require(StubURLProtocol.capturedRequest?.url)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems.contains(URLQueryItem(name: "path", value: "Photos")))
        #expect(queryItems.contains(URLQueryItem(name: "limit", value: "50")))
    }

    @Test
    func searchWithAnEmptyQueryStillSendsTheRequest() async throws {
        stub(statusCode: 200, body: #"{"items": []}"#.data(using: .utf8)!)
        let results = try await makeClient().search(serverURL, "", "", nil)
        #expect(results.isEmpty)
    }

    @Test
    func updatePreferenceEncodesTheKeyAndValueInThePATCHBody() async throws {
        stub(statusCode: 200, body: Data())
        StubURLProtocol.capturedRequest = nil
        try await makeClient().updatePreference(serverURL, .showHiddenFiles, true)
        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.httpMethod == "PATCH")
        let body = try #require(StubURLProtocol.capturedRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [String: Bool]])
        #expect(json["user"]?["showHiddenFiles"] == true)
    }

    // MARK: addFavorite / removeFavorite

    @Test
    func addFavoriteSendsThePathInThePOSTBodyAndDecodesTheCreatedFavorite() async throws {
        let favoriteJSON = """
        {"id": "f1", "path": "Photos", "label": null, "icon": "star", "color": null, "position": 0, "createdAt": "2024-01-01T00:00:00.000Z", "updatedAt": "2024-01-01T00:00:00.000Z"}
        """.data(using: .utf8)!
        stub(statusCode: 200, body: favoriteJSON)
        StubURLProtocol.capturedRequest = nil
        let favorite = try await makeClient().addFavorite(serverURL, "Photos")
        #expect(favorite.path == "Photos")
        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.httpMethod == "POST")
        let body = try #require(StubURLProtocol.capturedRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["path"] == "Photos")
    }

    @Test
    func addFavoriteMaps401ToSessionExpired() async throws {
        stub(statusCode: 401, body: Data())
        await #expect(throws: FilesClientError.sessionExpired) {
            _ = try await makeClient().addFavorite(serverURL, "Photos")
        }
    }

    @Test
    func removeFavoriteSendsThePathInTheDELETEBody() async throws {
        stub(statusCode: 200, body: #"[]"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        try await makeClient().removeFavorite(serverURL, "Photos")
        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.httpMethod == "DELETE")
        let body = try #require(StubURLProtocol.capturedRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["path"] == "Photos")
    }

    @Test
    func removeFavoriteMaps500ToServerErrorWithStatusCode() async throws {
        stub(statusCode: 500, body: Data())
        await #expect(throws: FilesClientError.server(statusCode: 500)) {
            try await makeClient().removeFavorite(serverURL, "Photos")
        }
    }

    // MARK: renameItem

    @Test
    func renameItemSendsTheParentPathOriginalNameAndNewNameAndDecodesTheRenamedItem() async throws {
        let renameJSON = """
        {"success": true, "item": {"name": "vacation-2024.jpg", "path": "Photos", "dateModified": "2024-01-01T00:00:00.000Z", "size": 1024, "kind": "jpg"}}
        """.data(using: .utf8)!
        stub(statusCode: 200, body: renameJSON)
        StubURLProtocol.capturedRequest = nil
        let item = FileItem(name: "vacation.jpg", path: "Photos", dateModified: Date(), size: 1024, kind: "jpg")
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
        let item = FileItem(name: "vacation.jpg", path: "Photos", dateModified: Date(), size: 0, kind: "jpg")
        await #expect(throws: FilesClientError.server(statusCode: 409)) {
            _ = try await makeClient().renameItem(serverURL, item, "taken.jpg")
        }
    }

    // MARK: deleteItems

    @Test
    func deleteItemsSendsPathNameAndKindForEveryItem() async throws {
        stub(statusCode: 200, body: #"{"success": true, "items": []}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        let first = FileItem(name: "a.txt", path: "Docs", dateModified: Date(), size: 0, kind: "txt")
        let second = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
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
        let item = FileItem(name: "readonly.txt", path: "", dateModified: Date(), size: 0, kind: "txt")
        await #expect(throws: FilesClientError.server(statusCode: 403)) {
            try await makeClient().deleteItems(serverURL, [item])
        }
    }

    @Test
    func deleteItemsWithAnEmptyArrayStillSendsTheRequest() async throws {
        stub(statusCode: 200, body: #"{"success": true, "items": []}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        try await makeClient().deleteItems(serverURL, [])
        let body = try #require(StubURLProtocol.capturedRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [[String: String]]])
        #expect(json["items"]?.isEmpty == true)
    }

    // MARK: transferItems

    @Test
    func transferItemsCopyPostsToCopyEndpointWithItemsAndDestination() async throws {
        let json = #"""
        {"success": true, "destination": "Documents", "items": [{"from": "Inbox/a.txt", "to": "Documents/a.txt"}]}
        """#.data(using: .utf8)!
        stub(statusCode: 200, body: json)
        StubURLProtocol.capturedRequest = nil
        let item = FileItem(name: "a.txt", path: "Inbox", dateModified: Date(), size: 0, kind: "txt")
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
        stub(statusCode: 200, body: #"{"success": true, "destination": "Archive", "items": []}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        let item = FileItem(name: "old", path: "", dateModified: Date(), size: 0, kind: "directory")
        _ = try await makeClient().transferItems(serverURL, [item], "Archive", .move)
        #expect(StubURLProtocol.capturedRequest?.url?.path == "/api/files/move")
    }

    @Test
    func transferItemsSurfacesAValidationMessageFromTheServer() async throws {
        stub(
            statusCode: 500,
            body: #"{"success": false, "error": {"message": "Cannot copy or move items to the root path."}}"#.data(using: .utf8)!
        )
        let item = FileItem(name: "a.txt", path: "Inbox", dateModified: Date(), size: 0, kind: "txt")
        await #expect(throws: FilesClientError.serverMessage(statusCode: 500, message: "Cannot copy or move items to the root path.")) {
            _ = try await makeClient().transferItems(serverURL, [item], "", .move)
        }
    }

    @Test
    func transferItemsMapsA401ToSessionExpired() async throws {
        stub(statusCode: 401, body: Data())
        let item = FileItem(name: "a.txt", path: "Inbox", dateModified: Date(), size: 0, kind: "txt")
        await #expect(throws: FilesClientError.sessionExpired) {
            _ = try await makeClient().transferItems(serverURL, [item], "Documents", .copy)
        }
    }

    // MARK: fetchMetadata

    @Test
    func fetchMetadataDecodesAPlainFileWithNoNestedMetadata() async throws {
        let json = """
        {"path": "Docs/notes.txt", "name": "notes.txt", "kind": "txt", "size": 128, "dateModified": "2024-01-01T00:00:00.000Z", "dateCreated": "2024-01-01T00:00:00.000Z"}
        """.data(using: .utf8)!
        stub(statusCode: 200, body: json)
        let metadata = try await makeClient().fetchMetadata(serverURL, "Docs/notes.txt")
        #expect(metadata.name == "notes.txt")
        #expect(metadata.image == nil)
    }

    @Test
    func fetchMetadataDecodesADirectorySummary() async throws {
        let json = """
        {"path": "Photos", "name": "Photos", "kind": "directory", "size": 4096, "dateModified": "2024-01-01T00:00:00.000Z", "dateCreated": "2024-01-01T00:00:00.000Z",
         "directory": {"totalSize": 10485760, "fileCount": 42, "dirCount": 3, "truncated": false}}
        """.data(using: .utf8)!
        stub(statusCode: 200, body: json)
        let metadata = try await makeClient().fetchMetadata(serverURL, "Photos")
        #expect(metadata.directory?.fileCount == 42)
    }

    @Test
    func fetchMetadataPercentEncodesEachPathSegment() async throws {
        stub(statusCode: 200, body: """
        {"path": "My Docs/#tag", "name": "#tag", "kind": "directory", "size": 0, "dateModified": "2024-01-01T00:00:00.000Z", "dateCreated": "2024-01-01T00:00:00.000Z"}
        """.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        _ = try await makeClient().fetchMetadata(serverURL, "My Docs/#tag")
        let url = try #require(StubURLProtocol.capturedRequest?.url)
        #expect(url.pathComponents.contains("#tag"))
    }

    @Test
    func fetchMetadataMapsForbiddenToAServerError() async throws {
        stub(statusCode: 403, body: Data())
        await #expect(throws: FilesClientError.server(statusCode: 403)) {
            _ = try await makeClient().fetchMetadata(serverURL, "Private")
        }
    }

    // MARK: thumbnailURL

    @Test
    func thumbnailURLResolvesAStaticCachedPathAgainstTheServerURL() async throws {
        stub(statusCode: 200, body: #"{"thumbnail": "/static/thumbnails/abc123.webp"}"#.data(using: .utf8)!)
        let url = try await makeClient().thumbnailURL(serverURL, "Photos/vacation.jpg")
        #expect(url == URL(string: "https://example.com/static/thumbnails/abc123.webp"))
    }

    @Test
    func thumbnailURLResolvesThePreviewFallbackPath() async throws {
        stub(statusCode: 200, body: #"{"thumbnail": "/api/preview?path=Photos%2Fvacation.jpg"}"#.data(using: .utf8)!)
        let url = try await makeClient().thumbnailURL(serverURL, "Photos/vacation.jpg")
        #expect(url?.absoluteString == "https://example.com/api/preview?path=Photos%2Fvacation.jpg")
    }

    @Test
    func thumbnailURLReturnsNilForAnEmptyThumbnailStringRatherThanAnError() async throws {
        stub(statusCode: 200, body: #"{"thumbnail": ""}"#.data(using: .utf8)!)
        let url = try await makeClient().thumbnailURL(serverURL, "notes.txt")
        #expect(url == nil)
    }

    @Test
    func thumbnailURLPercentEncodesEachPathSegment() async throws {
        stub(statusCode: 200, body: #"{"thumbnail": ""}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        _ = try await makeClient().thumbnailURL(serverURL, "My Docs/#tag.jpg")
        let url = try #require(StubURLProtocol.capturedRequest?.url)
        #expect(url.pathComponents.contains("#tag.jpg"))
    }

    @Test
    func thumbnailURLMapsSessionExpiredOn401() async throws {
        stub(statusCode: 401, body: Data())
        await #expect(throws: FilesClientError.sessionExpired) {
            _ = try await makeClient().thumbnailURL(serverURL, "Photos/vacation.jpg")
        }
    }

    // MARK: previewFile

    @Test
    func previewFileWritesTheResponseBodyToALocalFileNamedAfterTheItem() async throws {
        let body = Data("hello world".utf8)
        stub(statusCode: 200, body: body)
        let item = uniquePreviewItem(name: "notes.txt")

        let fileURL = try await makeClient().previewFile(serverURL, item)

        #expect(fileURL.lastPathComponent == item.name)
        #expect(try Data(contentsOf: fileURL) == body)
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    @Test
    func previewFileNamesRawImagesWithAJPEGExtensionSinceTheServerAlwaysConvertsThem() async throws {
        stub(statusCode: 200, body: Data("jpeg bytes".utf8))
        let item = uniquePreviewItem(name: "photo.nef", kind: "nef")

        let fileURL = try await makeClient().previewFile(serverURL, item)

        #expect(fileURL.lastPathComponent == "\(item.name).jpg")
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    @Test
    func previewFileSendsTheFullPathAsAQueryParameter() async throws {
        stub(statusCode: 200, body: Data())
        StubURLProtocol.capturedRequest = nil
        let item = uniquePreviewItem(name: "notes.txt", path: "Docs")

        let fileURL = try await makeClient().previewFile(serverURL, item)

        let url = try #require(StubURLProtocol.capturedRequest?.url)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems.contains(URLQueryItem(name: "path", value: "Docs/\(item.name)")))
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    @Test
    func previewFileReusesTheCachedFileForAnUnchangedItemWithoutHittingTheNetworkAgain() async throws {
        stub(statusCode: 200, body: Data("first".utf8))
        let item = uniquePreviewItem(name: "notes.txt")
        let firstURL = try await makeClient().previewFile(serverURL, item)

        // A second stub with different content: if the cache weren't reused, the returned
        // file would contain "second" instead.
        stub(statusCode: 200, body: Data("second".utf8))
        let secondURL = try await makeClient().previewFile(serverURL, item)

        #expect(firstURL == secondURL)
        #expect(try Data(contentsOf: secondURL) == Data("first".utf8))
        try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent())
    }

    @Test
    func previewFileRedownloadsWhenDateModifiedChangesEvenAtTheSamePath() async throws {
        stub(statusCode: 200, body: Data("first".utf8))
        let original = uniquePreviewItem(name: "notes.txt")
        let firstURL = try await makeClient().previewFile(serverURL, original)

        stub(statusCode: 200, body: Data("second".utf8))
        let changed = FileItem(
            name: original.name, path: original.path,
            dateModified: original.dateModified.addingTimeInterval(60), size: original.size, kind: original.kind
        )
        let secondURL = try await makeClient().previewFile(serverURL, changed)

        #expect(firstURL == secondURL) // same cache slot (same item path)...
        #expect(try Data(contentsOf: secondURL) == Data("second".utf8)) // ...but re-downloaded
        try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent())
    }

    @Test
    func previewFileMapsForbiddenToAServerError() async throws {
        stub(statusCode: 403, body: Data())
        let item = uniquePreviewItem(name: "secret.txt")
        await #expect(throws: FilesClientError.server(statusCode: 403)) {
            _ = try await makeClient().previewFile(serverURL, item)
        }
    }

    /// A distinct name per call (`UUID`-suffixed) keeps each test's cache slot
    /// (`Library/Caches/PreviewCache/<item.id>`) isolated from every other test and from any
    /// prior run — the cache is real, persistent disk state, not reset between test runs.
    private func uniquePreviewItem(name: String, path: String = "", kind: String = "txt") -> FileItem {
        let uniqueName = "\(UUID().uuidString)-\(name)"
        return FileItem(name: uniqueName, path: path, dateModified: Date(), size: 0, kind: kind)
    }

    // MARK: fetchTextContent / saveTextContent

    @Test
    func fetchTextContentDecodesTheContentFieldAndSendsTheFullPath() async throws {
        stub(statusCode: 200, body: #"{"content": "hello\nworld"}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil

        let content = try await makeClient().fetchTextContent(serverURL, "Docs/notes.md")

        #expect(content == "hello\nworld")
        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.httpMethod == "POST")
        let body = try #require(StubURLProtocol.capturedRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["path"] == "Docs/notes.md")
    }

    @Test
    func fetchTextContentMapsTooLargeOrBinaryValidationErrorsToAServerError() async throws {
        stub(statusCode: 400, body: Data())
        await #expect(throws: FilesClientError.server(statusCode: 400)) {
            _ = try await makeClient().fetchTextContent(serverURL, "movie.mp4")
        }
    }

    @Test
    func fetchTextContentMapsUnsupportedMediaTypeToAServerError() async throws {
        stub(statusCode: 415, body: Data())
        await #expect(throws: FilesClientError.server(statusCode: 415)) {
            _ = try await makeClient().fetchTextContent(serverURL, "binary.dat")
        }
    }

    @Test
    func saveTextContentSendsThePathAndContentAsAPUTBody() async throws {
        stub(statusCode: 200, body: #"{"success": true}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil

        try await makeClient().saveTextContent(serverURL, "Docs/notes.md", "updated content")

        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.httpMethod == "PUT")
        let body = try #require(StubURLProtocol.capturedRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["path"] == "Docs/notes.md")
        #expect(json["content"] == "updated content")
    }

    @Test
    func saveTextContentMapsReadOnlyPathToAServerError() async throws {
        stub(statusCode: 403, body: Data())
        await #expect(throws: FilesClientError.server(statusCode: 403)) {
            try await makeClient().saveTextContent(serverURL, "readonly/notes.md", "content")
        }
    }

    @Test
    func saveTextContentWithEmptyContentStillSendsTheRequest() async throws {
        stub(statusCode: 200, body: #"{"success": true}"#.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil

        try await makeClient().saveTextContent(serverURL, "Docs/empty.txt", "")

        let body = try #require(StubURLProtocol.capturedRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["content"] == "")
    }

    // MARK: extractZip

    @Test
    func extractZipHitsPlainAPIExtractPathNotAPIFilesExtract() async throws {
        // Regression coverage for a real bug this session: the endpoint is
        // `POST /api/files/zip/extract` (zip.js's own route path, mounted at plain `/api`) —
        // easy to get subtly wrong the same way `downloadRawFile` originally was.
        let json = #"{"success": true, "item": {"name": "bundle", "path": "", "dateModified": "2024-01-01T00:00:00.000Z", "size": 0, "kind": "directory"}}"#
        stub(statusCode: 201, body: json.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        let item = FileItem(name: "bundle.zip", path: "", dateModified: Date(), size: 0, kind: "zip")

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
        let item = FileItem(name: "bundle.rar", path: "", dateModified: Date(), size: 0, kind: "rar")
        await #expect(throws: FilesClientError.server(statusCode: 415)) {
            _ = try await makeClient().extractZip(serverURL, item)
        }
    }

    // MARK: downloadRawFile

    @Test
    func downloadRawFileHitsPlainAPIDownloadNotAPIFilesDownload() async throws {
        // Regression coverage: this endpoint's real path is `POST /api/download` — the
        // backend file lives at `routes/files/download.js` but is mounted at plain `/api` in
        // `routes/index.js`, not `/api/files`. Got this wrong once already (silent 404s on
        // every zip/rar/doc/docx preview until caught by live testing, not this test suite).
        stub(statusCode: 200, body: "raw file bytes".data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        let item = FileItem(name: "bundle.zip", path: "Archives", dateModified: Date(), size: 0, kind: "zip")

        _ = try await makeClient().downloadRawFile(serverURL, item)

        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/download")
        let body = try #require(StubURLProtocol.capturedRequestBody)
        let bodyJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(bodyJSON["path"] == "Archives/bundle.zip")
    }

    @Test
    func downloadRawFileMapsAccessDeniedToAServerError() async throws {
        stub(statusCode: 403, body: Data())
        let item = FileItem(name: "secret.docx", path: "", dateModified: Date(), size: 0, kind: "docx")
        await #expect(throws: FilesClientError.server(statusCode: 403)) {
            _ = try await makeClient().downloadRawFile(serverURL, item)
        }
    }

    // MARK: compressItem

    @Test
    func compressItemSendsItemsAndDestinationAndDecodesTheNewArchive() async throws {
        let json = #"{"success": true, "item": {"name": "Documents.zip", "path": "", "dateModified": "2024-01-01T00:00:00.000Z", "size": 2048, "kind": "zip"}}"#
        stub(statusCode: 201, body: json.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")

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
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")
        await #expect(throws: FilesClientError.server(statusCode: 403)) {
            _ = try await makeClient().compressItem(serverURL, item)
        }
    }

    // MARK: uploadFile

    private func makeTempFile(_ name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test
    func uploadFilePostsAMultipartEnvelopeToTheUploadEndpointAndDecodesTheStoredFile() async throws {
        let responseJSON = #"[{"name": "notes (1).txt", "path": "Inbox", "dateModified": "2024-01-01T00:00:00.000Z", "size": 12, "kind": "txt"}]"#
        stub(statusCode: 200, body: responseJSON.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        let fileURL = try makeTempFile("notes.txt", contents: "hello upload")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let stored = try await makeClient().uploadFile(serverURL, fileURL, "notes.txt", "Inbox") { _ in }

        #expect(stored.name == "notes (1).txt")
        #expect(stored.path == "Inbox")

        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/upload")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))

        let body = try #require(StubURLProtocol.capturedRequestBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        // Text fields must precede the file part, and the file bytes are included verbatim.
        let uploadToRange = try #require(bodyString.range(of: "name=\"uploadTo\""))
        let fileDataRange = try #require(bodyString.range(of: "name=\"filedata\"; filename=\"notes.txt\""))
        #expect(uploadToRange.lowerBound < fileDataRange.lowerBound)
        #expect(bodyString.contains("\r\n\r\nInbox\r\n"))
        #expect(bodyString.contains("\r\n\r\nnotes.txt\r\n"))
        #expect(bodyString.contains("hello upload"))
    }

    @Test
    func uploadFileSanitizesQuotesAndNewlinesOutOfTheHeaderFilename() async throws {
        let responseJSON = #"[{"name": "weird.txt", "path": "Inbox", "dateModified": "2024-01-01T00:00:00.000Z", "size": 1, "kind": "txt"}]"#
        stub(statusCode: 200, body: responseJSON.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        let fileURL = try makeTempFile("weird.txt", contents: "x")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try await makeClient().uploadFile(serverURL, fileURL, "we\"ir\nd.txt", "Inbox") { _ in }

        let body = try #require(StubURLProtocol.capturedRequestBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        #expect(bodyString.contains("filename=\"we'ir d.txt\""))
        // The unescaped name still rides the `relativePath` field verbatim for the server.
        #expect(bodyString.contains("name=\"relativePath\"\r\n\r\nwe\"ir\nd.txt\r\n"))
    }

    @Test
    func uploadFileSurfacesTheServerMessageOnRejection() async throws {
        let errorJSON = #"{"error": {"message": "Cannot upload files to this path."}}"#
        stub(statusCode: 403, body: errorJSON.data(using: .utf8)!)
        let fileURL = try makeTempFile("notes.txt", contents: "x")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: FilesClientError.serverMessage(statusCode: 403, message: "Cannot upload files to this path.")) {
            _ = try await makeClient().uploadFile(serverURL, fileURL, "notes.txt", "Inbox") { _ in }
        }
    }

    // MARK: updateShareLink

    private static let shareJSON = #"""
    {"id": "s1", "shareToken": "AbC123xyz0", "ownerId": "u1", "sourcePath": "Docs/Report",
     "isDirectory": true, "accessMode": "readwrite", "sharingType": "anyone", "hasPassword": false,
     "expiresAt": null, "label": "Report", "downloadCount": 0, "lastAccessedAt": null,
     "createdAt": "2027-01-15T10:00:00.000Z", "updatedAt": "2027-01-16T10:00:00.000Z"}
    """#

    private func updateBody(_ request: UpdateShareRequest) async throws -> [String: Any] {
        stub(statusCode: 200, body: Self.shareJSON.data(using: .utf8)!)
        StubURLProtocol.capturedRequest = nil
        _ = try await makeClient().updateShareLink(serverURL, "s1", request)
        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://example.com/api/shares/s1")
        let data = try #require(StubURLProtocol.capturedRequestBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test
    func updateShareLinkOmitsThePasswordKeyWhenKeeping() async throws {
        let body = try await updateBody(UpdateShareRequest(label: "New", accessMode: .readonly, target: .anyone, password: .keep))
        #expect(body["password"] == nil)
        #expect(body["label"] as? String == "New")
        #expect(body["accessMode"] as? String == "readonly")
        #expect(body["userIds"] == nil) // not a users share
    }

    @Test
    func updateShareLinkSendsNullToRemoveThePassword() async throws {
        let body = try await updateBody(UpdateShareRequest(password: .remove))
        #expect(body["password"] is NSNull)
    }

    @Test
    func updateShareLinkSendsTheStringToChangeThePassword() async throws {
        let body = try await updateBody(UpdateShareRequest(password: .set("hunter2")))
        #expect(body["password"] as? String == "hunter2")
    }

    @Test
    func updateShareLinkIncludesUserIdsOnlyForAUsersShare() async throws {
        let body = try await updateBody(UpdateShareRequest(target: .users, userIds: ["u2", "u3"], password: .keep))
        #expect(body["userIds"] as? [String] == ["u2", "u3"])
        #expect(body["sharingType"] as? String == "users")
    }

    @Test
    func updateShareLinkMapsAForbiddenResponseToAServerError() async throws {
        stub(statusCode: 403, body: Data())
        await #expect(throws: FilesClientError.server(statusCode: 403)) {
            _ = try await makeClient().updateShareLink(serverURL, "s1", UpdateShareRequest())
        }
    }
}
