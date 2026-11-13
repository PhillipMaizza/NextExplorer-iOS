import CoreGraphics
import Foundation
@testable import ShareUploads
import Testing
import TestUtils
import UniformTypeIdentifiers

/// The one image and PDF renderer the app and the share extension share.
@Suite("Thumbnail rendering")
struct ThumbnailRenderingTests {
    private enum Constants {
        static let maxPixel: CGFloat = 32
        static let jpegQuality: CGFloat = 0.8
        static let garbage = Data([0x00, 0x01, 0x02, 0x03])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailRendering-\(TestID.uuid().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A picture is scaled so its longest side fits, keeping its shape")
    func aPictureFitsItsLongestSide() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (url, _) = try ThumbnailFixture.png(in: root)

        let image = try #require(ThumbnailRendering.image(at: url, maxPixel: Constants.maxPixel))

        #expect(image.width == 32)
        #expect(image.height == 24)
    }

    @Test("A PDF's first page is drawn at the page's shape, longest side fitting")
    func aPDFPageKeepsItsShape() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try ThumbnailFixture.pdf(in: root)

        let image = try #require(ThumbnailRendering.firstPDFPage(at: url, maxPixel: Constants.maxPixel))

        #expect(image.width == 24)
        #expect(image.height == 32)
    }

    @Test("A file is rendered by its type: a picture, a PDF, nothing for anything else")
    func aFileIsRenderedByItsType() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (png, _) = try ThumbnailFixture.png(in: root)
        let pdf = try ThumbnailFixture.pdf(in: root)

        #expect(ThumbnailRendering.thumbnail(of: png, type: .png, maxPixel: Constants.maxPixel) != nil)
        #expect(ThumbnailRendering.thumbnail(of: pdf, type: .pdf, maxPixel: Constants.maxPixel) != nil)
        #expect(ThumbnailRendering.thumbnail(of: png, type: .plainText, maxPixel: Constants.maxPixel) == nil)
        #expect(ThumbnailRendering.thumbnail(of: png, type: nil, maxPixel: Constants.maxPixel) == nil)
    }

    @Test("Bytes that are not an image give nothing instead of failing")
    func garbageGivesNothing() {
        #expect(ThumbnailRendering.image(from: Constants.garbage, maxPixel: Constants.maxPixel) == nil)
    }

    @Test("A JPEG made from an image decodes back to that image's size")
    func aJPEGDecodesBack() throws {
        let image = try ThumbnailFixture.filledImage(size: ThumbnailFixture.imageSize)

        let jpeg = try #require(ThumbnailRendering.jpegData(image, quality: Constants.jpegQuality))
        let decoded = try #require(ThumbnailRendering.image(from: jpeg, maxPixel: ThumbnailFixture.imageSize.width))

        #expect(decoded.width == 64)
        #expect(decoded.height == 48)
    }
}
