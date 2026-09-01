import AVFoundation
import DesignSystem
import SwiftUI
import UIKit

private enum Constants {
    static let playBadgeFraction: CGFloat = 0.4
    static let playBadgeShadowRadius: CGFloat = 2
    static let renderScale: CGFloat = 3
    static let hiddenOpacity: Double = 0
    static let shownOpacity: Double = 1
    static let frameTime = CMTime(seconds: 0, preferredTimescale: 60)
}

/// A first frame thumbnail for a locally staged video, generated once with
/// `AVAssetImageGenerator` and marked with a play glyph so a row of picked media reads which
/// items are footage. Mirrors how `AsyncImage` renders picked photos: a pure view concern with
/// a neutral placeholder until the frame is ready.
struct VideoThumbnailView: View {
    let url: URL
    let size: CGFloat

    @State private var frame: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let frame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFill()
            } else if didFail {
                FileTypeIcon(kind: url.pathExtension)
            } else {
                ThumbnailLoadingPlaceholder()
            }
            IconKit.playCircle
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: size * Constants.playBadgeFraction, height: size * Constants.playBadgeFraction)
                .shadow(radius: Constants.playBadgeShadowRadius)
                .opacity(frame == nil ? Constants.hiddenOpacity : Constants.shownOpacity)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: .radiusSmall))
        .task(id: url) {
            if let image = await Self.firstFrame(of: url, maxPixelSize: size * Constants.renderScale) {
                frame = image
            } else if !Task.isCancelled {
                // A cancelled generate (row scrolled away) is not a failure; leave the
                // placeholder so re-appearing retries instead of dropping to the generic icon.
                didFail = true
            }
        }
    }

    private static func firstFrame(of url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let cgImage = try? await generator.image(at: Constants.frameTime).image else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
