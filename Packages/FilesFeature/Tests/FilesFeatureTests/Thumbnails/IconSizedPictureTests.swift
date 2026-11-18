import CoreGraphics
import DesignSystem
@testable import FilesFeature
import Testing

/// A picture too small to fill a grid well is drawn as an icon instead of stretched.
@MainActor
struct IconSizedPictureTests {
    private func image(side: Int) -> PlatformImage? {
        PlatformImageRenderer.image(size: CGSize(width: side, height: side), opaque: true) { _ in }
    }

    @Test
    func aFaviconIsIconSized() throws {
        #expect(try ThumbnailImage.isIconSized(#require(image(side: 32))))
        #expect(try ThumbnailImage.isIconSized(#require(image(side: 128))))
    }

    @Test
    func aPhotoThumbnailFillsTheWell() throws {
        #expect(try !ThumbnailImage.isIconSized(#require(image(side: 129))))
    }
}
