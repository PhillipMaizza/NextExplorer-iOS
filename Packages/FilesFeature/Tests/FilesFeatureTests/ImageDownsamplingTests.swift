import CoreGraphics
import DesignSystem
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

struct ImageDownsamplingTests {
    private enum Constants {
        static let sourceWidth: CGFloat = 200
        static let sourceHeight: CGFloat = 100
        static let filePrefix = "image-downsampling-"
        static let notAnImage = Data("not an image".utf8)
    }

    private func sourceImageData() throws -> Data {
        let image = try #require(PlatformImageRenderer.image(size: CGSize(width: Constants.sourceWidth, height: Constants.sourceHeight), opaque: true) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: Constants.sourceWidth, height: Constants.sourceHeight))
        })
        return try #require(image.jpegData(compressionQuality: 1))
    }

    private func pixelSize(_ image: PlatformImage?) throws -> CGSize {
        let cgImage = try #require(image?.cgImage)
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    @Test
    func theLongestSideIsScaledDownToTheRequestedPixelsKeepingTheAspectRatio() throws {
        let image = try ImageDownsampling.image(from: sourceImageData(), maxPixelDimension: 50)

        #expect(try pixelSize(image) == CGSize(width: 50, height: 25))
    }

    @Test
    func aZeroOrNegativeLimitIsClampedToOnePixel() throws {
        let data = try sourceImageData()

        #expect(try pixelSize(ImageDownsampling.image(from: data, maxPixelDimension: 0)).width == 1)
        #expect(try pixelSize(ImageDownsampling.image(from: data, maxPixelDimension: -40)).width == 1)
    }

    @Test
    func bytesThatAreNotAnImageGiveNoImage() {
        #expect(ImageDownsampling.image(from: Constants.notAnImage, maxPixelDimension: 50) == nil)
        #expect(ImageDownsampling.image(from: Data(), maxPixelDimension: 50) == nil)
    }

    @Test
    func aFileIsDownsampledTheSameWayAsItsBytes() throws {
        let data = try sourceImageData()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(Constants.filePrefix)\(TestID.name()).jpg")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try pixelSize(ImageDownsampling.image(from: url, maxPixelDimension: 50)) == CGSize(width: 50, height: 25))
    }

    @Test
    func aMissingOrNonImageFileGivesNoImage() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(Constants.filePrefix)\(TestID.name())")
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(Constants.filePrefix)\(TestID.name()).txt")
        try Constants.notAnImage.write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }

        #expect(ImageDownsampling.image(from: missing, maxPixelDimension: 50) == nil)
        #expect(ImageDownsampling.image(from: text, maxPixelDimension: 50) == nil)
    }
}
