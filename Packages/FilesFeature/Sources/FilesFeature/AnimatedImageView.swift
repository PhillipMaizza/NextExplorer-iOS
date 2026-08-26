import ImageIO
import SwiftUI
import UIKit

/// Plays an animated GIF — `AsyncImage`/SwiftUI's `Image` only ever show a GIF's first frame,
/// with no concept of animation at all, so a real animated GIF looked identical to a still
/// image everywhere in this app. Decodes every frame via ImageIO and hands the result to a
/// plain `UIImageView`, which does animate multi-frame `UIImage`s natively.
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
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            // A .gif with only one frame isn't actually animated — decode it normally.
            return UIImage(data: data)
        }

        var frames: [UIImage] = []
        var totalDuration: Double = 0
        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            totalDuration += frameDuration(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: totalDuration > 0 ? totalDuration : Double(frames.count) * 0.1)
    }

    /// Mirrors how browsers/Apple's own GIF decoders read frame timing: prefer the
    /// unclamped delay, fall back to the clamped one, and treat anything under ~20ms as a
    /// (common, deliberately-abused) authoring bug rather than a real near-zero delay.
    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let delay = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gifProperties[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}
