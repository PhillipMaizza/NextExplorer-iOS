import SwiftUI

#if os(iOS)
    import UIKit

    public typealias PlatformImage = UIImage

    public extension Image {
        init(platformImage: PlatformImage) {
            self.init(uiImage: platformImage)
        }
    }
#elseif os(macOS)
    import AppKit

    public typealias PlatformImage = NSImage

    public extension NSImage {
        /// Mirrors `UIImage(cgImage:)`: a zero size makes AppKit use the bitmap's pixel size.
        convenience init(cgImage: CGImage) {
            self.init(cgImage: cgImage, size: .zero)
        }

        var cgImage: CGImage? {
            cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        func jpegData(compressionQuality: CGFloat) -> Data? {
            guard let cgImage else { return nil }
            return NSBitmapImageRep(cgImage: cgImage)
                .representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        }

        /// AppKit decodes lazily per draw; resolving the bitmap once here front loads that cost.
        func preparingForDisplay() -> NSImage? {
            cgImage.map { NSImage(cgImage: $0) }
        }
    }

    public extension Image {
        init(platformImage: PlatformImage) {
            self.init(nsImage: platformImage)
        }
    }
#endif

/// Scale 1 bitmap drawn straight through CoreGraphics, so it is safe off the main thread on
/// both platforms. The context keeps the CoreGraphics bottom left origin.
public enum PlatformImageRenderer {
    public static func image(size: CGSize, opaque: Bool, _ draw: (CGContext) -> Void) -> PlatformImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) else { return nil }
        draw(context)
        return context.makeImage().map { PlatformImage(cgImage: $0) }
    }
}

@MainActor
public enum PlatformScreen {
    public static var bounds: CGRect {
        #if os(iOS)
            UIScreen.main.bounds
        #else
            NSScreen.main?.frame ?? .zero
        #endif
    }

    public static var scale: CGFloat {
        #if os(iOS)
            UIScreen.main.scale
        #else
            NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }
}
