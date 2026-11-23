import DesignSystem
import SwiftUI

enum ThumbnailFill {
    case fit
    case crop
    case backdrop
}

struct ThumbnailPicture: View {
    private enum Metrics {
        static let backdropBlur: CGFloat = .size24
    }

    let image: PlatformImage
    let fill: ThumbnailFill

    var body: some View {
        switch fill {
        case .fit:
            fitted
        case .crop:
            cropped
        case .backdrop:
            fitted
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { cropped.blur(radius: Metrics.backdropBlur) }
                .clipped()
        }
    }

    private var fitted: some View {
        Image(platformImage: image)
            .resizable()
            .scaledToFit()
    }

    private var cropped: some View {
        Image(platformImage: image)
            .resizable()
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
    }
}

private enum PreviewFixture {
    static let banner = PlatformImageRenderer.image(size: CGSize(width: 820, height: 312), opaque: true) { context in
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 820, height: 312))
        context.setFillColor(CGColor(red: 1, green: 0.7, blue: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 310, y: 56, width: 200, height: 200))
    }
}

#Preview("Fills") {
    HStack(spacing: .space16) {
        ForEach([ThumbnailFill.fit, .crop, .backdrop], id: \.self) { fill in
            if let banner = PreviewFixture.banner {
                ThumbnailPicture(image: banner, fill: fill)
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous))
            }
        }
    }
    .padding()
}
