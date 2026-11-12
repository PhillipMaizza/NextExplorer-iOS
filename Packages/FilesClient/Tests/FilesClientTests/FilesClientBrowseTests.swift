import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// `browse`, conditional GET, prefetch and `search` through `FilesClient.live` against a stubbed `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite
    struct FilesClientBrowseTests: FilesClientLiveHarness {
        @Test
        func browseDecodesASuccessfulResponse() async throws {
            stub(statusCode: 200, body: try browseResultJSON)
            let result = try await makeClient().browse(serverURL, "")
            #expect(result.items.map(\.name) == ["Docs"])
            #expect(result.access.canRead == true)
        }

        @Test
        func browsePreservesListingWhenAnOutsideSymlinkHasNullSize() async throws {
            var body = try #require(JSONSerialization.jsonObject(with: try browseResultJSON) as? [String: Any])
            var items = try #require(body["items"] as? [[String: Any]])
            var entry = try #require(items.first)
            entry["name"] = "outside-link"
            entry["kind"] = "unknown"
            entry["size"] = NSNull()
            entry["link"] = "outside"
            items.append(entry)
            body["items"] = items
            try stub(statusCode: 200, body: JSONSerialization.data(withJSONObject: body))

            let result = try await makeClient().browse(serverURL, "Home")

            #expect(result.items.map(\.name) == ["Docs", "outside-link"])
            #expect(result.items.last?.size == 0)
            #expect(result.access.canRead)
        }

        @Test
        func browseDecodesFractionalSecondISO8601Dates() async throws {
            stub(statusCode: 200, body: try browseResultJSON)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let result = try await makeClient().browse(serverURL, "")
            #expect(result.items.first?.dateModified == formatter.date(from: "2024-01-01T00:00:00.000Z"))
        }

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
        func browseMapsOfflineFailureToAnOfflineError() async throws {
            StubURLProtocol.stub = nil
            StubURLProtocol.failure = URLError(.notConnectedToInternet)
            await #expect(throws: FilesClientError.offline) {
                _ = try await makeClient().browse(serverURL, "")
            }
        }

        @Test
        func browseMapsOtherTransportFailureToANetworkError() async throws {
            StubURLProtocol.stub = nil
            StubURLProtocol.failure = URLError(.badServerResponse)
            let error = await #expect(throws: FilesClientError.self) {
                _ = try await makeClient().browse(serverURL, "")
            }
            guard case .network = error else {
                Issue.record("expected .network, got \(String(describing: error))")
                return
            }
        }

        @Test
        func browseWritesResultThroughToTheDirectoryCache() async throws {
            stub(statusCode: 200, body: try browseResultJSON)
            let store = DirectoryCacheStore.inMemory()
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store,
                now: { Date(timeIntervalSince1970: 42) }
            )
            let result = try await client.browse(serverURL, "docs")

            let cached = store.read(serverURL: serverURL, path: "docs")
            #expect(cached?.items.map(\.name) == result.items.map(\.name))
            #expect(cached?.fetchedAt == Date(timeIntervalSince1970: 42))
        }

        @Test
        func lateResponseWritesTheScopeCapturedAtRequestStart() async throws {
            stub(statusCode: 200, body: try browseResultJSON)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("late-write-\(TestID.name())")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = DirectoryCacheStore.onDisk(rootDirectory: root)
            let activeScope = LockIsolated("account-a")
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store,
                now: {
                    activeScope.setValue("account-b")
                    return Date(timeIntervalSince1970: 7)
                },
                activeScope: { activeScope.value }
            )

            _ = try await client.browse(serverURL, "docs")

            #expect(store.bound(to: "account-a").read(serverURL: serverURL, path: "docs") != nil)
            #expect(store.bound(to: "account-b").read(serverURL: serverURL, path: "docs") == nil)
        }

        @Test
        func browseDoesNotWriteThroughOnFailure() async {
            StubURLProtocol.stub = nil
            StubURLProtocol.failure = URLError(.notConnectedToInternet)
            let store = DirectoryCacheStore.inMemory()
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store
            )
            _ = try? await client.browse(serverURL, "docs")
            #expect(store.read(serverURL: serverURL, path: "docs") == nil)
        }

        @Test
        func browseStoresTheServerETagAndSendsItAsIfNoneMatchOnTheNextFetch() async throws {
            let store = DirectoryCacheStore.inMemory()
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store,
                now: { Date(timeIntervalSince1970: 1) }
            )

            stub(statusCode: 200, body: try browseResultJSON, headers: ["Content-Type": "application/json", "ETag": "\"v1\""])
            _ = try await client.browse(serverURL, "docs")
            #expect(store.read(serverURL: serverURL, path: "docs")?.etag == "\"v1\"")

            StubURLProtocol.capturedRequest = nil
            stub(statusCode: 200, body: try browseResultJSON, headers: ["Content-Type": "application/json", "ETag": "\"v2\""])
            _ = try await client.browse(serverURL, "docs")
            #expect(StubURLProtocol.capturedRequest?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
            #expect(store.read(serverURL: serverURL, path: "docs")?.etag == "\"v2\"")
        }

        @Test
        func browseReturnsTheCachedListingOnA304() async throws {
            let store = DirectoryCacheStore.inMemory()
            let cachedItem = FileItem(name: "Saved", path: "docs", dateModified: Date(timeIntervalSince1970: 0), size: 1, kind: "txt")
            store.write(
                serverURL: serverURL, path: "docs",
                result: BrowseResult(
                    items: [cachedItem],
                    access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
                    path: "docs"
                ),
                etag: "\"v1\"",
                fetchedAt: Date(timeIntervalSince1970: 0)
            )

            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store,
                now: { Date(timeIntervalSince1970: 500) }
            )
            stub(statusCode: 304, body: Data(), headers: ["ETag": "\"v1\""])

            let result = try await client.browse(serverURL, "docs")
            #expect(result.items.map(\.name) == ["Saved"])
            // The 304 refreshes the entry's timestamp so a prefetch freshness check sees it as current.
            #expect(store.read(serverURL: serverURL, path: "docs")?.fetchedAt == Date(timeIntervalSince1970: 500))
            #expect(store.read(serverURL: serverURL, path: "docs")?.etag == "\"v1\"")
        }

        @Test
        func prefetchDirectoryWritesThroughOverTheLowPrioritySession() async throws {
            stub(statusCode: 200, body: try browseResultJSON, headers: ["Content-Type": "application/json", "ETag": "\"pf\""])
            let store = DirectoryCacheStore.inMemory()
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store,
                now: { Date(timeIntervalSince1970: 7) }
            )

            await client.prefetchDirectory(serverURL, "docs/sub")

            let cached = store.read(serverURL: serverURL, path: "docs/sub")
            #expect(cached?.items.map(\.name) == ["Docs"])
            #expect(cached?.etag == "\"pf\"")
            #expect(cached?.fetchedAt == Date(timeIntervalSince1970: 7))
        }

        @Test
        func prefetchDirectorySwallowsFailures() async {
            StubURLProtocol.stub = nil
            StubURLProtocol.failure = URLError(.notConnectedToInternet)
            let store = DirectoryCacheStore.inMemory()
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store
            )

            await client.prefetchDirectory(serverURL, "docs/sub")
            #expect(store.read(serverURL: serverURL, path: "docs/sub") == nil)
        }

        @Test
        func browsePercentEncodesPathSegmentsWithSpecialCharacters() async throws {
            stub(statusCode: 200, body: try browseResultJSON)
            StubURLProtocol.capturedRequest = nil
            _ = try await makeClient().browse(serverURL, "My Docs/#tag/日本語")
            let url = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(url.path.contains("My%20Docs") || url.path.contains("My Docs"))
            #expect(url.pathComponents.contains("#tag"))
            #expect(url.pathComponents.contains("日本語"))
        }

        @Test
        func browseOfAnEmptyPathHitsTheRootBrowseEndpointWithATrailingSlash() async throws {
            stub(statusCode: 200, body: try browseResultJSON)
            StubURLProtocol.capturedRequest = nil
            _ = try await makeClient().browse(serverURL, "")
            let url = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(url.absoluteString.hasSuffix("/api/browse/"))
        }

        @Test
        func browseOfTheRootFallsBackToTheVolumesListWhenTheRootIsRefused() async throws {
            defer { StubURLProtocol.pathStubs = [:] }
            let volumesJSON = try FilesClientFixture.browseVolumesList.data()
            let notFound = try FilesClientFixture.browseErrorVolumeAccessDenied.data()
            StubURLProtocol.failure = nil
            StubURLProtocol.stub = nil
            StubURLProtocol.pathStubs = [
                "/api/browse": .init(statusCode: 404, headers: ["Content-Type": "application/json"], body: notFound),
                "/api/volumes": .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: volumesJSON),
            ]
            let store = DirectoryCacheStore.inMemory()
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store
            )

            let result = try await client.browse(serverURL, "")

            #expect(result.items.map(\.name) == ["center-projekt", "k9"])
            #expect(result.items.allSatisfy { $0.isDirectory && $0.path.isEmpty && !$0.hasKnownDate })
            #expect(result.access.canWrite == false)
            #expect(store.read(serverURL: serverURL, path: "")?.items.map(\.name) == ["center-projekt", "k9"])
        }

        @Test
        func browseOfASubfolderDoesNotFallBackToTheVolumesListOnA404() async {
            stub(statusCode: 404, body: Data())
            await #expect(throws: FilesClientError.server(statusCode: 404)) {
                try await makeClient().browse(serverURL, "k9/missing")
            }
        }

        @Test
        func searchOmitsPathAndLimitQueryItemsWhenNotProvided() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.commonItemsEmpty.data())
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
            stub(statusCode: 200, body: try FilesClientFixture.commonItemsEmpty.data())
            StubURLProtocol.capturedRequest = nil
            _ = try await makeClient().search(serverURL, "Photos", "vacation", 50)
            let url = try #require(StubURLProtocol.capturedRequest?.url)
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(queryItems.contains(URLQueryItem(name: "path", value: "Photos")))
            #expect(queryItems.contains(URLQueryItem(name: "limit", value: "50")))
        }

        @Test
        func searchKeepsTheServerOrderAndSaysWhyItFallsShort() async throws {
            let body = try FilesClientFixture.searchMixedMatches.string()
            stub(statusCode: 200, body: body.data(using: .utf8)!)
            let page = try await makeClient().search(serverURL, "", "zeta", 2)
            #expect(page.items.map(\.name) == ["zeta.txt", "alpha.txt"])
            #expect(page.items.map(\.matchKind) == [.name, .contents])
            #expect(!page.isTruncated)
            #expect(!page.isComplete)
            #expect(page.limit == 2)
        }

        @Test
        func searchFromAnOlderServerReadsAsComplete() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.searchSingleDirectory.data())
            let page = try await makeClient().search(serverURL, "", "abc", nil)
            #expect(page.isComplete)
            #expect(!page.isTruncated)
            #expect(page.items.first?.matchKind == nil)
        }
    }
}
