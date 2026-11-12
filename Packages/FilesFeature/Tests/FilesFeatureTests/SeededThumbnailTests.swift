import ComposableArchitecture
import CoreGraphics
@testable import FilesFeature
import Foundation
import ShareUploads
import Testing
import TestUtils

/// Reading the thumbnail seeded for a file shared into the app, for a folder row or PDF cell.
@Suite("Seeded thumbnails in the folder")
struct SeededThumbnailTests {
    private enum Constants {
        static let path = "Photos/beach.jpg"
        static let size: Int64 = 2048
        static let pixels = 32
        static let maxPixel: CGFloat = 16
        static let eightDays: TimeInterval = 8 * 24 * 60 * 60
        static let jpegQuality: CGFloat = 0.8
    }

    private func jpeg() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: Constants.pixels, height: Constants.pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Constants.pixels, height: Constants.pixels))
        let image = try #require(context.makeImage())
        return try #require(ThumbnailRendering.jpegData(image, quality: Constants.jpegQuality))
    }

    /// A store that answers `data` and counts how often it was asked.
    private func store(answering data: Data?, lookups: LockIsolated<Int>) -> LocalThumbnailStore {
        var store = LocalThumbnailStore.testValue
        store.thumbnail = { _, _, _ in
            lookups.withValue { $0 += 1 }
            return data
        }
        return store
    }

    @Test("A recent file with a seed shows it, downsampled")
    func aRecentFileShowsItsSeed() async throws {
        let lookups = LockIsolated(0)
        let image = try await SeededThumbnail.image(
            from: store(answering: jpeg(), lookups: lookups), path: Constants.path, size: Constants.size,
            modified: MockDate.date, maxPixel: Constants.maxPixel, priority: .userInitiated, now: MockDate.date
        )

        #expect(image != nil)
        #expect(lookups.value == 1)
    }

    @Test("A recent file without a seed has none")
    func aRecentFileWithoutASeedHasNone() async {
        let lookups = LockIsolated(0)
        let image = await SeededThumbnail.image(
            from: store(answering: nil, lookups: lookups), path: Constants.path, size: Constants.size,
            modified: MockDate.date, maxPixel: Constants.maxPixel, priority: .userInitiated, now: MockDate.date
        )

        #expect(image == nil)
        #expect(lookups.value == 1)
    }

    @Test("A file too old to have a seed skips the disk lookup entirely")
    func anOldFileSkipsTheLookup() async throws {
        let lookups = LockIsolated(0)
        let image = try await SeededThumbnail.image(
            from: store(answering: jpeg(), lookups: lookups), path: Constants.path, size: Constants.size,
            modified: MockDate.date, maxPixel: Constants.maxPixel, priority: .userInitiated,
            now: MockDate.date.addingTimeInterval(Constants.eightDays)
        )

        #expect(image == nil)
        #expect(lookups.value == 0)
    }
}
