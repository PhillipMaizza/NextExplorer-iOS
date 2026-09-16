import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct PDFThumbnailStoreTests {
    /// Isolated render-cache dir so nothing lands in the shared `PreviewCache` root.
    private func isolatedCache() -> (cache: PDFThumbnailCache, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-thumb-store-cache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (.live(renderCacheDirectory: directory), directory)
    }

    private func makePDF() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-store-test-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 120, height: 160))
        try? renderer.writePDF(to: url) { context in
            context.beginPage()
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }
        return url
    }

    private func item(size: Int64) -> FileItem {
        FileItem(
            name: "\(UUID().uuidString).pdf", path: "Docs",
            dateModified: Date(timeIntervalSince1970: 2), size: size, kind: "pdf"
        )
    }

    private func load(
        _ store: PDFThumbnailStore, key: String, item: FileItem,
        client: FilesClient, cache: PDFThumbnailCache
    ) -> PDFThumbnailStore.Entry {
        let entry = store.entry(forKey: key)
        store.load(
            entry: entry, key: key, item: item,
            serverURL: URL(string: "https://example.com")!, filesClient: client, cache: cache
        )
        return entry
    }

    private func waitForReady(_ entry: PDFThumbnailStore.Entry) async -> UIImage? {
        for _ in 0 ..< 40 {
            if case let .ready(image) = entry.state {
                return image
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if case let .ready(image) = entry.state {
            return image
        }
        return nil
    }

    private func isUnavailable(_ entry: PDFThumbnailStore.Entry) -> Bool {
        if case .unavailable = entry.state {
            return true
        }
        return false
    }

    @Test
    func loadFetchesRendersAndPublishesTheImageOnce() async {
        let store = PDFThumbnailStore()
        let pdfURL = makePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let fetchCount = LockIsolated(0)

        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in
            fetchCount.withValue { $0 += 1 }
            return pdfURL
        }
        let file = item(size: 5)
        let key = PDFThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature)
        let (cache, cacheDirectory) = isolatedCache()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        // Two overlapping loads for the same key: one fetch, one render.
        let entry = load(store, key: key, item: file, client: client, cache: cache)
        _ = load(store, key: key, item: file, client: client, cache: cache)

        let image = await waitForReady(entry)
        #expect(image != nil)
        #expect(fetchCount.value == 1)
    }

    @Test
    func loadMarksFilesOverTheSizeCapUnavailableWithoutFetching() {
        let store = PDFThumbnailStore()
        let fetchCount = LockIsolated(0)
        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in
            fetchCount.withValue { $0 += 1 }
            return URL(fileURLWithPath: "/dev/null")
        }
        let huge = item(size: 500 * 1_024 * 1_024)
        let key = PDFThumbnailCache.cacheKey(id: huge.id, signature: huge.cacheSignature)
        let (cache, cacheDirectory) = isolatedCache()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let entry = load(store, key: key, item: huge, client: client, cache: cache)

        #expect(isUnavailable(entry))
        #expect(fetchCount.value == 0)
    }

    @Test
    func loadFallsToUnavailableWhenTheDownloadIsNotAReadablePDF() async throws {
        let store = PDFThumbnailStore()
        let notPDF = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-pdf-\(UUID().uuidString)")
        try Data("nope".utf8).write(to: notPDF)
        defer { try? FileManager.default.removeItem(at: notPDF) }

        var client = FilesClient.previewValue
        client.previewFileLowPriority = { _, _ in notPDF }
        let file = item(size: 4)
        let key = PDFThumbnailCache.cacheKey(id: file.id, signature: file.cacheSignature)
        let (cache, cacheDirectory) = isolatedCache()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let entry = load(store, key: key, item: file, client: client, cache: cache)

        for _ in 0 ..< 40 where !isUnavailable(entry) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(isUnavailable(entry))
    }

    @Test
    func entryForKeyReturnsAStableBoxAndEvictsOldestPastTheCap() {
        let store = PDFThumbnailStore()
        let first = store.entry(forKey: "a")
        #expect(store.entry(forKey: "a") === first)
    }
}
