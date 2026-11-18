import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
@testable import FilesFeature
import Foundation
import ShareUploads
import Testing
import TestUtils

@MainActor
@Suite(.serialized)
struct DocumentThumbnailStoreTests {
    /// Isolated render-cache dir so nothing lands in the shared `PreviewCache` root.
    private func isolatedCache() -> (cache: DocumentThumbnailCache, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-thumb-store-cache-\(TestID.name())", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (.live(renderCacheDirectory: directory), directory)
    }

    private func makePDF() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-store-test-\(TestID.name()).pdf")
        PDFFixture.write(to: url, pageSize: CGSize(width: 120, height: 160), red: 0.19, green: 0.69, blue: 0.78)
        return url
    }

    private func item(size: Int64, kind: String = TestKind.pdf) -> FileItem {
        FileItem(
            name: "\(TestID.name()).\(kind)", path: TestFolder.docs,
            dateModified: MockDate.date.addingTimeInterval(2), size: size, kind: kind
        )
    }

    private func load(
        _ store: DocumentThumbnailStore, key: String, item: FileItem,
        client: FilesClient, cache: DocumentThumbnailCache, localThumbnails: LocalThumbnailStore = .testValue
    ) -> (entry: DocumentThumbnailStore.Entry, task: Task<Void, Never>?) {
        let entry = store.entry(forKey: key)
        let task = store.load(
            entry: entry, key: key, item: item,
            serverURL: URL(string: TestHost.exampleURLString)!, filesClient: client, cache: cache,
            localThumbnails: localThumbnails, now: MockDate.date
        )
        return (entry, task)
    }

    private func readyImage(_ entry: DocumentThumbnailStore.Entry) -> PlatformImage? {
        if case let .ready(image) = entry.state {
            return image
        }
        return nil
    }

    private func isUnavailable(_ entry: DocumentThumbnailStore.Entry) -> Bool {
        if case .unavailable = entry.state {
            return true
        }
        return false
    }

    @Test
    func aPDFSharedIntoTheAppShowsItsSeededPageWithoutDownloading() async {
        let store = DocumentThumbnailStore()
        let pdfURL = makePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let seed = ThumbnailRendering.firstPDFPage(at: pdfURL, maxPixel: 64).flatMap { ThumbnailRendering.jpegData(
            $0,
            quality: 0.8
        ) }
        let fetchCount = LockIsolated(0)
        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in
            fetchCount.withValue { $0 += 1 }
            return pdfURL
        }
        var seeds = LocalThumbnailStore.testValue
        seeds.thumbnail = { _, _, _ in seed }
        let file = item(size: 5)
        let key = DocumentThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature)
        let (cache, cacheDirectory) = isolatedCache()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let (entry, task) = load(store, key: key, item: file, client: client, cache: cache, localThumbnails: seeds)
        await task?.value

        #expect(seed != nil)
        #expect(readyImage(entry) != nil)
        #expect(fetchCount.value == 0)
    }

    @Test
    func loadFetchesRendersAndPublishesTheImageOnce() async {
        let store = DocumentThumbnailStore()
        let pdfURL = makePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let fetchCount = LockIsolated(0)

        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in
            fetchCount.withValue { $0 += 1 }
            return pdfURL
        }
        let file = item(size: 5)
        let key = DocumentThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature)
        let (cache, cacheDirectory) = isolatedCache()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        // Two overlapping loads for the same key: one fetch, one render.
        let (entry, task) = load(store, key: key, item: file, client: client, cache: cache)
        _ = load(store, key: key, item: file, client: client, cache: cache)

        await task?.value
        let image = readyImage(entry)
        #expect(image != nil)
        #expect(fetchCount.value == 1)
    }

    @Test
    func loadMarksFilesOverTheSizeCapUnavailableWithoutFetching() {
        let store = DocumentThumbnailStore()
        let fetchCount = LockIsolated(0)
        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in
            fetchCount.withValue { $0 += 1 }
            return URL(fileURLWithPath: "/dev/null")
        }
        let huge = item(size: 500 * 1_024 * 1_024)
        let key = DocumentThumbnailCache.cacheKey(id: huge.id, signature: huge.cacheSignature)
        let (cache, cacheDirectory) = isolatedCache()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let entry = load(store, key: key, item: huge, client: client, cache: cache).entry

        #expect(isUnavailable(entry))
        #expect(fetchCount.value == 0)
    }

    @Test
    func loadFallsToUnavailableWhenTheDownloadIsNotAReadablePDF() async throws {
        let store = DocumentThumbnailStore()
        let notPDF = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-pdf-\(TestID.name())")
        try Data(TestAccount.rejectedPassword.utf8).write(to: notPDF)
        defer { try? FileManager.default.removeItem(at: notPDF) }

        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in notPDF }
        let file = item(size: 4)
        let key = DocumentThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature)
        let (cache, cacheDirectory) = isolatedCache()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let (entry, task) = load(store, key: key, item: file, client: client, cache: cache)

        await task?.value
        #expect(isUnavailable(entry))
    }

    @Test
    func eligibilityFollowsTheKindAndItsSizeCap() {
        let megabyte: Int64 = 1_024 * 1_024
        #expect(DocumentThumbnailStore.isEligible(item(size: 40 * megabyte)))
        #expect(!DocumentThumbnailStore.isEligible(item(size: 40 * megabyte + 1)))
        #expect(DocumentThumbnailStore.isEligible(item(size: 10 * megabyte, kind: TestKind.word)))
        #expect(!DocumentThumbnailStore.isEligible(item(size: 10 * megabyte + 1, kind: TestKind.word)))
        #expect(DocumentThumbnailStore.isEligible(item(size: 5, kind: "pages")))
        #expect(!DocumentThumbnailStore.isEligible(item(size: 0, kind: TestKind.word)))
        #expect(!DocumentThumbnailStore.isEligible(item(size: 5, kind: TestKind.archive)))
    }

    @Test
    func aWordDocumentComesDownRawAndIsDrawnFromThatFile() async throws {
        let store = DocumentThumbnailStore()
        let rawURL = makePDF()
        defer { try? FileManager.default.removeItem(at: rawURL) }
        let page = try #require(ThumbnailRendering.firstPDFPage(at: rawURL, maxPixel: 16))
        let previewCount = LockIsolated(0)
        let drawnFrom = LockIsolated<URL?>(nil)
        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in
            previewCount.withValue { $0 += 1 }
            return rawURL
        }
        client.downloadRawFileLowPriority = { _, _ in rawURL }
        let cache = DocumentThumbnailCache { _, _, fileURL in
            drawnFrom.setValue(fileURL)
            return PlatformImage(cgImage: page)
        }
        let file = item(size: 5, kind: TestKind.word)
        let key = DocumentThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature)

        let (entry, task) = load(store, key: key, item: file, client: client, cache: cache)
        await task?.value

        #expect(readyImage(entry) != nil)
        #expect(drawnFrom.value == rawURL)
        #expect(previewCount.value == 0)
    }

    @Test
    func removeAllForgetsEveryEntry() {
        let store = DocumentThumbnailStore()
        let first = store.entry(forKey: "a")
        store.removeAll()
        #expect(store.entry(forKey: "a") !== first)
    }

    @Test
    func entryForKeyReturnsAStableBoxAndEvictsOldestPastTheCap() {
        let store = DocumentThumbnailStore()
        let first = store.entry(forKey: "a")
        #expect(store.entry(forKey: "a") === first)
    }
}
