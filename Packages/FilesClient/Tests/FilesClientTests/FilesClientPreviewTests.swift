import CoreModels
import Dependencies
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Preview, thumbnail and preview cache behavior through `FilesClient.live` against a stubbed `URLSession`. Nested in `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares
/// `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    struct FilesClientPreviewTests: FilesClientLiveHarness {
        /// A distinct name per call (`UUID`-suffixed) keeps each test's cache slot
        /// (`Library/Caches/PreviewCache/<item.id>`) isolated from every other test and from any
        /// prior run: the cache is real, persistent disk state, not reset between test runs.
        func uniquePreviewItem(name: String, path: String = "", kind: String = "txt") -> FileItem {
            let uniqueName = "\(TestID.name())-\(name)"
            return FileItem(name: uniqueName, path: path, dateModified: MockDate.date, size: 0, kind: kind)
        }

        @Test
        func previewFileLowPriorityFetchesFromPreviewThenSharesTheCacheSlotWithPreviewFile() async throws {
            let item = FileItem(
                name: "\(TestID.name()).pdf", path: TestFolder.docs,
                dateModified: MockDate.date.addingTimeInterval(1), size: 3, kind: TestKind.pdf
            )
            stub(statusCode: 200, body: Data("PDF".utf8))
            let client = makeClient()

            StubURLProtocol.capturedRequest = nil
            let downloaded = try await client.previewFileLowPriority(serverURL, item)
            let requestURL = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(requestURL.path.hasPrefix("/api/preview"))
            #expect(FileManager.default.fileExists(atPath: downloaded.path))
            defer { try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent()) }

            // Second low priority call: cache hit, no request.
            StubURLProtocol.capturedRequest = nil
            let again = try await client.previewFileLowPriority(serverURL, item)
            #expect(again == downloaded)
            #expect(StubURLProtocol.capturedRequest == nil)

            // The interactive path lands in the same slot, so tap-to-open reuses the download.
            StubURLProtocol.capturedRequest = nil
            let interactive = try await client.previewFile(serverURL, item)
            #expect(interactive == downloaded)
            #expect(StubURLProtocol.capturedRequest == nil)
        }

        @Test
        func thumbnailURLResolvesAStaticCachedPathAgainstTheServerURL() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.previewThumbnailStaticPath.data())
            let url = try await makeClient().thumbnailURL(serverURL, Constants.vacationPhoto)
            #expect(url == URL(string: "https://example.com/static/thumbnails/abc123.webp"))
        }

        @Test
        func thumbnailURLResolvesThePreviewFallbackPath() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.previewThumbnailPreviewQuery.data())
            let url = try await makeClient().thumbnailURL(serverURL, Constants.vacationPhoto)
            #expect(url?.absoluteString == "https://example.com/api/preview?path=Photos%2Fvacation.jpg")
        }

        @Test
        func thumbnailURLReturnsNilForAnEmptyThumbnailStringRatherThanAnError() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.previewThumbnailEmpty.data())
            let url = try await makeClient().thumbnailURL(serverURL, TestFile.notes)
            #expect(url == nil)
        }

        @Test
        func thumbnailURLPercentEncodesEachPathSegment() async throws {
            try stub(statusCode: 200, body: FilesClientFixture.previewThumbnailEmpty.data())
            StubURLProtocol.capturedRequest = nil
            _ = try await makeClient().thumbnailURL(serverURL, "My Docs/#tag.jpg")
            let url = try #require(StubURLProtocol.capturedRequest?.url)
            #expect(url.pathComponents.contains("#tag.jpg"))
        }

        @Test
        func thumbnailURLMapsSessionExpiredOn401() async throws {
            stub(statusCode: 401, body: Data())
            await #expect(throws: FilesClientError.sessionExpired) {
                _ = try await makeClient().thumbnailURL(serverURL, Constants.vacationPhoto)
            }
        }

        @Test
        func previewFileWritesTheResponseBodyToALocalFileNamedAfterTheItem() async throws {
            let body = Data("hello world".utf8)
            stub(statusCode: 200, body: body)
            let item = uniquePreviewItem(name: TestFile.notes)

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
            let item = uniquePreviewItem(name: TestFile.notes, path: TestFolder.docs)

            let fileURL = try await makeClient().previewFile(serverURL, item)

            let url = try #require(StubURLProtocol.capturedRequest?.url)
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(queryItems.contains(URLQueryItem(name: "path", value: "Docs/\(item.name)")))
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        @Test
        func previewFileReusesTheCachedFileForAnUnchangedItemWithoutHittingTheNetworkAgain() async throws {
            stub(statusCode: 200, body: Data("first".utf8))
            let item = uniquePreviewItem(name: TestFile.notes)
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
            let original = uniquePreviewItem(name: TestFile.notes)
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
            await #expect(throws: FilesClientError.forbidden(message: nil)) {
                _ = try await makeClient().previewFile(serverURL, item)
            }
        }

        @Test
        func previewFileKeepsATraversingServerNameInsideThePreviewCache() async throws {
            stub(statusCode: 200, body: Data("payload".utf8))
            // A hostile directory listing returns a name that would climb out of the cache dir.
            let item = FileItem(
                name: "../../../../\(TestID.name())-escape.txt",
                path: "Docs/\(TestID.name())", dateModified: MockDate.date, size: 0, kind: TestKind.text
            )

            let fileURL = try await makeClient().previewFile(serverURL, item).standardizedFileURL
            defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

            let cachesRoot = try FileManager.default
                .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("PreviewCache", isDirectory: true).standardizedFileURL
            #expect(fileURL.path.hasPrefix(cachesRoot.path + "/"))
            #expect(!fileURL.pathComponents.contains(".."))
            #expect(fileURL.lastPathComponent == "escape.txt" || fileURL.lastPathComponent.hasSuffix("-escape.txt"))
        }

        @Test
        func downloadRawFileKeepsATraversingServerNameInsideThePreviewCache() async throws {
            stub(statusCode: 200, body: Data("payload".utf8))
            let item = FileItem(
                name: "../../../../\(TestID.name())-escape.bin",
                path: "Docs/\(TestID.name())", dateModified: MockDate.date, size: 0, kind: "bin"
            )

            let fileURL = try await makeClient().downloadRawFile(serverURL, item).standardizedFileURL
            defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

            let cachesRoot = try FileManager.default
                .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("PreviewCache", isDirectory: true).standardizedFileURL
            #expect(fileURL.path.hasPrefix(cachesRoot.path + "/"))
            #expect(!fileURL.pathComponents.contains(".."))
        }

        @Test
        func evictionNeverDeletesTheSlotItWasAskedToProtect() throws {
            let item = FileItem(name: "huge-\(TestID.name()).mkv", path: "Evict", dateModified: MockDate.date, size: 600_000_000, kind: "mkv")
            let slot = FilesService.previewCacheDirectory(for: item, namespace: FilesService.rawDownloadCacheNamespace)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            let fileURL = slot.appendingPathComponent(item.name)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.truncate(atOffset: UInt64(FilesService.previewCacheMaxBytes) + 1)
            try handle.close()
            defer { try? FileManager.default.removeItem(at: slot) }

            FilesService.evictPreviewCacheIfNeeded(protecting: slot)
            #expect(FileManager.default.fileExists(atPath: fileURL.path), "the file just downloaded must survive even when it alone exceeds the budget")

            FilesService.evictPreviewCacheIfNeeded()
            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }
    }
}

private enum Constants {
    static let vacationPhoto = "Photos/vacation.jpg"
}
