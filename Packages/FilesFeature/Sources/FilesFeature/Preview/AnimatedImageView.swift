import ImageIO
import SwiftUI
import UIKit

private enum Constants {
    /// Hard cap on how many frames are decoded, however many the file claims. Above this the
    /// source frames are sampled evenly and each kept frame's delay is scaled up to preserve
    /// the overall loop duration.
    static let maxFrameCount = 300
    /// Per-frame ceiling before the decoded-bytes budget tightens it further.
    static let maxFramePixelDimension: CGFloat = 1024
    /// Ceiling on the total decoded bitmap held for playback (~4 bytes/px). A backstop against
    /// a huge or deliberately crafted "GIF" — a real animated GIF is far under this. Frames
    /// are downsampled so `frameCount * dimension^2 * 4` stays within it.
    static let maxDecodedBytes = 256 * 1024 * 1024
    static let fallbackFrameDelay: Double = 0.1
    static let minFrameDelay: Double = 0.02
}

/// Plays an animated GIF — `AsyncImage`/SwiftUI's `Image` only ever show a GIF's first frame,
/// with no concept of animation at all, so a real animated GIF looked identical to a still
/// image everywhere in this app. Decodes frames via ImageIO (downsampled, frame-count and
/// total-bitmap capped) and hands the result to a plain `UIImageView`, which animates
/// multi-frame `UIImage`s natively.
struct AnimatedImageView: UIViewRepresentable {
    let fileURL: URL

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.image = Self.decodeAnimatedImage(at: fileURL)
        imageView.startAnimating()
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    private static func decodeAnimatedImage(at url: URL) -> UIImage? {
        // `CGImageSourceCreateWithURL` memory-maps the file rather than reading it all into a
        // resident `Data` first.
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let sourceFrameCount = CGImageSourceGetCount(source)
        guard sourceFrameCount > 1 else {
            // Not actually animated — decode the single frame, still downsampled.
            return ImageDownsampling.image(from: url, maxPixelDimension: Constants.maxFramePixelDimension)
        }

        let frameCount = min(sourceFrameCount, Constants.maxFrameCount)
        let stride = max(1, sourceFrameCount / frameCount)
        let dimensionForBudget = (Double(Constants.maxDecodedBytes) / (Double(frameCount) * 4)).squareRoot()
        let maxPixelDimension = min(Constants.maxFramePixelDimension, CGFloat(dimensionForBudget))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelDimension)
        ]

        var frames: [UIImage] = []
        var totalDuration: Double = 0
        var sourceIndex = 0
        while sourceIndex < sourceFrameCount, frames.count < frameCount {
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, sourceIndex, thumbnailOptions as CFDictionary) {
                frames.append(UIImage(cgImage: cgImage))
                // Scale by `stride` so subsampling doesn't speed the loop up.
                totalDuration += frameDuration(source: source, index: sourceIndex) * Double(stride)
            }
            sourceIndex += stride
        }
        guard !frames.isEmpty else { return nil }
        let duration = totalDuration > 0 ? totalDuration : Double(frames.count) * Constants.fallbackFrameDelay
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    /// Mirrors how browsers/Apple's own GIF decoders read frame timing: prefer the
    /// unclamped delay, fall back to the clamped one, and treat anything under ~20ms as a
    /// (common, deliberately-abused) authoring bug rather than a real near-zero delay.
    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return Constants.fallbackFrameDelay
        }
        let delay = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gifProperties[kCGImagePropertyGIFDelayTime] as? Double)
            ?? Constants.fallbackFrameDelay
        return delay < Constants.minFrameDelay ? Constants.fallbackFrameDelay : delay
    }
}
