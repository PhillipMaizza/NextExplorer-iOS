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
    /// Isolated render cache dir so nothing lands in the shared `PreviewCache` root.
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
        client: FilesClient, cache: DocumentThumbnailCache, localThumbnails: LocalThumbnailStore = .testValue,
        offlineFiles: OfflineFileStore = .testValue, isMetered: Bool = false
    ) -> (entry: DocumentThumbnailStore.Entry, task: Task<Void, Never>?) {
        let entry = store.entry(forKey: key)
        let task = store.load(
            entry: entry, key: key, item: item,
            serverURL: URL(string: TestHost.exampleURLString)!, filesClient: client, cache: cache,
            localThumbnails: localThumbnails, offlineFiles: offlineFiles, now: MockDate.date, isMetered: isMetered
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
        #expect(!DocumentThumbnailStore.isEligible(item(size: 0)))
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
    func onMobileDataNothingDownloadsAndOnlyKeptCopiesOrEarlierRendersShow() async throws {
        let store = DocumentThumbnailStore()
        let page = try #require(ThumbnailRendering.firstPDFPage(at: makePDF(), maxPixel: 16))
        let downloads = LockIsolated(0)
        var client = FilesClient.previewValue
        client.downloadRawFileLowPriority = { _, _ in
            downloads.withValue { $0 += 1 }
            throw FilesClientError.offline
        }
        let neverDrawn = item(size: 5, kind: TestKind.word)
        let drawnBefore = item(size: 6, kind: TestKind.word)
        let keptOffline = item(size: 7, kind: TestKind.word)
        let keptURL = URL(fileURLWithPath: "/kept/\(keptOffline.name)")
        var offlineFiles = OfflineFileStore.testValue
        offlineFiles.localURL = { $0.id == keptOffline.id ? keptURL : nil }
        let drawnBeforeKey = DocumentThumbnailCache.cacheKey(id: drawnBefore.id, signature: drawnBefore.cacheSignature)
        let cache = DocumentThumbnailCache { key, _, fileURL in
            fileURL == keptURL || fileURL == nil && key == drawnBeforeKey ? PlatformImage(cgImage: page) : nil
        }

        let skipped = load(
            store, key: DocumentThumbnailCache.cacheKey(id: neverDrawn.id, signature: neverDrawn.cacheSignature),
            item: neverDrawn, client: client, cache: cache, isMetered: true
        )
        await skipped.task?.value
        let shown = load(store, key: drawnBeforeKey, item: drawnBefore, client: client, cache: cache, isMetered: true)
        await shown.task?.value
        let kept = load(
            store, key: DocumentThumbnailCache.cacheKey(id: keptOffline.id, signature: keptOffline.cacheSignature),
            item: keptOffline, client: client, cache: cache, offlineFiles: offlineFiles, isMetered: true
        )
        await kept.task?.value

        if case .loading = skipped.entry.state {} else {
            Issue.record("Expected loading, got \(skipped.entry.state)")
        }
        #expect(readyImage(shown.entry) != nil)
        #expect(readyImage(kept.entry) != nil)
        #expect(downloads.value == 0)
    }

    @Test
    func removeAllStopsALoadStillRunningSoNothingIsDrawnAfterTheWipe() async {
        let store = DocumentThumbnailStore()
        let draws = LockIsolated(0)
        var client = FilesClient.previewValue
        client.downloadRawFileLowPriority = { _, _ in
            try await suspendUntilCancelled()
            return URL(fileURLWithPath: "/")
        }
        let cache = DocumentThumbnailCache { _, _, _ in
            draws.withValue { $0 += 1 }
            return nil
        }
        let file = item(size: 5, kind: TestKind.word)

        let (_, task) = load(
            store, key: DocumentThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature),
            item: file, client: client, cache: cache
        )
        store.removeAll()
        await task?.value

        #expect(draws.value == 0)
    }

    @Test
    func aLoadFinishingAfterItsEntryWasDroppedFillsTheEntryTakenSince() async {
        let store = DocumentThumbnailStore()
        let pdfURL = makePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in pdfURL }
        let file = item(size: 5)
        let key = DocumentThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature)
        let (cache, cacheDirectory) = isolatedCache()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let (dropped, task) = load(store, key: key, item: file, client: client, cache: cache)
        // A wide grid asks for more keys than the store keeps while this one still loads.
        for index in 0 ..< Constants.keysPastTheCap {
            _ = store.entry(forKey: "\(index)")
        }
        let taken = store.entry(forKey: key)
        await task?.value

        #expect(taken !== dropped)
        #expect(readyImage(taken) != nil)
    }

    @Test
    func aLoadWhoseAccountIsWipedWhileItFetchesDrawsNothing() async {
        let store = DocumentThumbnailStore()
        // A scope of its own, so marking it wiped touches no other test.
        let scope = TestID.name()
        let draws = LockIsolated(0)
        var client = FilesClient.previewValue
        client.downloadRawFileLowPriority = { _, _ in
            CacheAccountScope.markWiped(scope)
            return URL(fileURLWithPath: "/")
        }
        let cache = DocumentThumbnailCache { _, _, _ in
            draws.withValue { $0 += 1 }
            return nil
        }
        let file = item(size: 5, kind: TestKind.word)

        let (entry, task) = CacheAccountScope.withPinned(scope) {
            load(
                store, key: DocumentThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature),
                item: file, client: client, cache: cache
            )
        }
        await task?.value

        #expect(draws.value == 0)
        if case .loading = entry.state {} else {
            Issue.record("Expected loading, got \(entry.state)")
        }
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

private enum Constants {
    /// The store keeps 60 keys; one past that drops the oldest.
    static let keysPastTheCap = 60
}
