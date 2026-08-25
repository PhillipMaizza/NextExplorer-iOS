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
}
