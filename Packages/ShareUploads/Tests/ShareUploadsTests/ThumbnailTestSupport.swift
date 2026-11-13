import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Small image and PDF files on disk, for the thumbnail rendering and seeding tests.
enum ThumbnailFixture {
    static let pngName = "beach.png"
    static let pdfName = "scan.pdf"
    static let imageSize = CGSize(width: 64, height: 48)
    static let pageSize = CGSize(width: 120, height: 160)

    /// A filled PNG of `imageSize` in `root`, and its byte size.
    static func png(in root: URL) throws -> (url: URL, size: Int64) {
        let image = try filledImage(size: imageSize)
        let url = root.appendingPathComponent(pngName)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let size = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        return (url, Int64(size))
    }

    /// A one page PDF of `pageSize` in `root`.
    static func pdf(in root: URL) throws -> URL {
        let url = root.appendingPathComponent(pdfName)
        var box = CGRect(origin: .zero, size: pageSize)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return url
    }

    static func filledImage(size: CGSize) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        return try #require(context.makeImage())
    }
}
