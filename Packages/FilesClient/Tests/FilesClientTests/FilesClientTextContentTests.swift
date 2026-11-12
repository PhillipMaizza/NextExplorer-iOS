import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Text content reads and writes, including offline reads of a pinned copy, through `FilesClient.live` against a stubbed `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    @Suite
    struct FilesClientTextContentTests: FilesClientLiveHarness {
        func pinnedTextClient(scope: String, bytes: Data) throws -> FilesClient {
            let pinned = FileItem(name: "n.txt", path: "Docs", dateModified: Date(timeIntervalSince1970: 0), size: Int64(bytes.count), kind: "txt")
            let source = FileManager.default.temporaryDirectory.appendingPathComponent("pin-text-\(TestID.name())")
            try bytes.write(to: source)
            _ = try OfflineCache.store(downloadedURL: source, item: pinned, scope: scope)
            StubURLProtocol.failure = URLError(.timedOut)
            return FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: .testValue,
                activeScope: { scope }
            )
        }

        @Test
        func fetchTextContentDecodesTheContentFieldAndSendsTheFullPath() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.textContentHelloWorld.data())
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
            stub(statusCode: 200, body: try FilesClientFixture.commonSuccessTrue.data())
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
            await #expect(throws: FilesClientError.forbidden(message: nil)) {
                try await makeClient().saveTextContent(serverURL, "readonly/notes.md", "content")
            }
        }

        @Test
        func saveTextContentWithEmptyContentStillSendsTheRequest() async throws {
            stub(statusCode: 200, body: try FilesClientFixture.commonSuccessTrue.data())
            StubURLProtocol.capturedRequest = nil

            try await makeClient().saveTextContent(serverURL, "Docs/empty.txt", "")

            let body = try #require(StubURLProtocol.capturedRequestBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["content"] == "")
        }

        @Test
        func anOfflineTextReadUsesThePinnedCopyOfTheCapturedScopeNotTheGlobalOne() async throws {
            resetStubs()
            let scope = "offline-text-\(TestID.name())"
            defer { OfflineCache.removeScope(scope) }
            let client = try pinnedTextClient(scope: scope, bytes: Data("pinned text".utf8))

            #expect(try await client.fetchTextContent(serverURL, "Docs/n.txt") == "pinned text")
            resetStubs()
        }

        @Test
        func anOfflineTextReadRefusesAPinnedCopyAboveTheBackendEditorCap() async throws {
            resetStubs()
            let scope = "offline-text-\(TestID.name())"
            defer { OfflineCache.removeScope(scope) }
            let cap = FilesService.EditorLimits.maxFileSizeBytes
            let client = try pinnedTextClient(scope: scope, bytes: Data(repeating: UInt8(ascii: "a"), count: cap + 1))

            await #expect(throws: FilesClientError.offline) {
                _ = try await client.fetchTextContent(serverURL, "Docs/n.txt")
            }
            resetStubs()
        }

        @Test
        func anOfflineTextReadAcceptsAPinnedCopyExactlyAtTheCap() async throws {
            resetStubs()
            let scope = "offline-text-\(TestID.name())"
            defer { OfflineCache.removeScope(scope) }
            let cap = FilesService.EditorLimits.maxFileSizeBytes
            let client = try pinnedTextClient(scope: scope, bytes: Data(repeating: UInt8(ascii: "a"), count: cap))

            #expect(try await client.fetchTextContent(serverURL, "Docs/n.txt").utf8.count == cap)
            resetStubs()
        }

        @Test
        func anOfflineTextReadRefusesBinaryBytesWithNulInsteadOfOpeningGarbage() async throws {
            resetStubs()
            let scope = "offline-text-\(TestID.name())"
            defer { OfflineCache.removeScope(scope) }
            let client = try pinnedTextClient(scope: scope, bytes: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02, 0x00, 0xFF]))

            await #expect(throws: FilesClientError.offline) {
                _ = try await client.fetchTextContent(serverURL, "Docs/n.txt")
            }
            resetStubs()
        }

        @Test
        func aDirectlySeededInMemoryStoreIsVisibleToALiveClientUnderTheSameNonEmptyScope() async throws {
            resetStubs()
            let scope = "scope-seeded"
            let store = DirectoryCacheStore.inMemory(scope: scope)
            let seeded = BrowseResult(
                items: [FileItem(name: "cached.txt", path: "Docs", dateModified: Date(timeIntervalSince1970: 0), size: 1, kind: "txt")],
                access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
                path: "Docs"
            )
            store.write(serverURL: serverURL, path: "Docs", result: seeded, etag: #"W/"v1""#, fetchedAt: Date(timeIntervalSince1970: 0))
            StubURLProtocol.stub = .init(statusCode: 304, headers: [:], body: Data())
            let client = FilesClient.live(
                networkClient: .live(protocolClasses: [StubURLProtocol.self]),
                directoryCacheStore: store,
                activeScope: { scope }
            )

            let browsed = try await client.browse(serverURL, "Docs")

            #expect(browsed.items.map(\.name) == ["cached.txt"])
            resetStubs()
        }
    }
}
