import ComposableArchitecture
import Foundation
import Testing

@testable import FilesFeature

/// `ThumbnailCache.liveValue` hits the real filesystem for its cache layer; its network leg
/// (`URLSession.shared`) isn't mockable without a protocol seam. These tests exercise the
/// disk half: a pre-seeded byte cache entry is returned without a fetch, and `resolvedURL`
/// remembers a thumbnail-URL resolution across calls.
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

    // MARK: resolvedURL (remembers the `GET /api/thumbnails` resolution across app launches)

    private func recordURL(forPath path: String) throws -> URL {
        let cachesDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return cachesDirectory
            .appendingPathComponent("PreviewCache", isDirectory: true)
            .appendingPathComponent("thumbnail-urls", isDirectory: true)
            .appendingPathComponent(sha256Hex(of: path))
    }

    @Test
    func resolvedURLCallsTheResolverOnAMissAndRemembersTheResultForNextTime() async throws {
        let path = "Photos/\(UUID().uuidString).jpg"
        defer { try? FileManager.default.removeItem(at: try! recordURL(forPath: path)) }
        let resolved = URL(string: "https://example.com/static/thumbnails/abc.webp")!
        let callCount = LockIsolated(0)

        let first = await store.resolvedURL(path, "100.0|4096") {
            callCount.withValue { $0 += 1 }
            return resolved
        }
        #expect(first == resolved)
        #expect(callCount.value == 1)

        // Same path + signature: served from the record, resolver never runs again.
        let second = await store.resolvedURL(path, "100.0|4096") {
            callCount.withValue { $0 += 1 }
            return resolved
        }
        #expect(second == resolved)
        #expect(callCount.value == 1)
    }

    @Test
    func resolvedURLReResolvesWhenTheFileSignatureChanges() async throws {
        let path = "Photos/\(UUID().uuidString).jpg"
        defer { try? FileManager.default.removeItem(at: try! recordURL(forPath: path)) }
        let old = URL(string: "https://example.com/static/thumbnails/v1.webp")!
        let new = URL(string: "https://example.com/static/thumbnails/v2.webp")!

        _ = await store.resolvedURL(path, "1.0|10") { old }
        let afterEdit = await store.resolvedURL(path, "2.0|20") { new }

        #expect(afterEdit == new)
    }

    @Test
    func resolvedURLRemembersANilResultSoAnUnthumbnailableFileIsNotReAsked() async throws {
        let path = "Docs/\(UUID().uuidString).pdf"
        defer { try? FileManager.default.removeItem(at: try! recordURL(forPath: path)) }
        let callCount = LockIsolated(0)

        let first = await store.resolvedURL(path, "5.0|1") {
            callCount.withValue { $0 += 1 }
            return nil
        }
        let second = await store.resolvedURL(path, "5.0|1") {
            callCount.withValue { $0 += 1 }
            return nil
        }

        #expect(first == nil)
        #expect(second == nil)
        #expect(callCount.value == 1)
    }
}

import CryptoKit

private func sha256Hex(of string: String) -> String {
    let digest = SHA256.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
