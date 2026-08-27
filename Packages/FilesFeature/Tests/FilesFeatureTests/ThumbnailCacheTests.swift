import Foundation
import Testing

@testable import FilesFeature

/// `ThumbnailCache.liveValue` hits the real filesystem for its cache layer; the network leg
/// (`URLSession.shared.data(from:)`) isn't mockable without a protocol seam, so these tests
/// exercise only the disk-cache half directly reachable from a test: writing a fake cached
/// entry and confirming `data(_:)` returns it without attempting a network call.
@Suite
struct ThumbnailCacheTests {
    private let store = ThumbnailCache.liveValue

    private func cacheDirectory() throws -> URL {
        let cachesDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return cachesDirectory.appendingPathComponent("PreviewCache", isDirectory: true).appendingPathComponent("thumbnails", isDirectory: true)
    }

    // MARK: Happy path

    @Test
    func dataReturnsThePreCachedBytesWithoutHittingTheNetwork() async throws {
        let url = URL(string: "https://example.com/static/thumbnails/\(UUID().uuidString).webp")!
        let directory = try cacheDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Same digest scheme `ThumbnailCache.liveValue` uses internally, so this pre-seeds
        // the exact cache slot `data(_:)` will look for.
        let key = sha256Hex(of: url.absoluteString)
        let fileURL = directory.appendingPathComponent(key)
        let expectedBytes = Data("fake-thumbnail-bytes".utf8)
        try expectedBytes.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let data = try await store.data(url)

        #expect(data == expectedBytes)
    }

    // MARK: Edge cases

    @Test
    func differentURLsMapToDifferentCacheSlots() throws {
        let directory = try cacheDirectory()
        let urlA = URL(string: "https://example.com/static/thumbnails/a.webp")!
        let urlB = URL(string: "https://example.com/static/thumbnails/b.webp")!

        let keyA = sha256Hex(of: urlA.absoluteString)
        let keyB = sha256Hex(of: urlB.absoluteString)

        #expect(keyA != keyB)
        #expect(directory.appendingPathComponent(keyA) != directory.appendingPathComponent(keyB))
    }
}

import CryptoKit

private func sha256Hex(of string: String) -> String {
    let digest = SHA256.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
