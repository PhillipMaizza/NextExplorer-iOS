import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    /// The box every symbol fits in, as shares of the well's shorter side: a page and a chip
    /// beside it line up.
    static let widthFraction: CGFloat = 0.4
    static let heightFraction: CGFloat = 0.52
    static let spacing: CGFloat = .size6
    static let labelMinScale: CGFloat = 0.7
    static let previewWidth: CGFloat = 110
    static let playSize: CGFloat = 22
    static let playGlyphSize: CGFloat = 9
    static let playInset: CGFloat = .size6
    static let playBackdropOpacity: Double = 0.5
}

/// What a grid well shows when it is not a full picture: a page or a type icon, centred in one
/// shared box. `content` gets the well's shorter side to size itself by.
struct GridWellSymbol<Content: View>: View {
    let kind: String
    /// Names the type under the symbol, for a file with no preview; a page says what it is already.
    var showsLabel = false
    @ViewBuilder let content: (_ wellSide: CGFloat) -> Content

    /// The largest a page may be in a well of `side`.
    static func pageBox(wellSide side: CGFloat) -> CGSize {
        CGSize(width: side * Constants.widthFraction, height: side * Constants.heightFraction)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let box = Self.pageBox(wellSide: side)
            VStack(spacing: Constants.spacing) {
                content(side)
                    .frame(maxWidth: box.width, maxHeight: box.height)
                if showsLabel, !kind.isEmpty, kind != FileItem.unknownKind {
                    Text(kind.uppercased())
                        .type(.caption(.semibold), style: .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(Constants.labelMinScale)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// The small play mark in the corner of a video frame or a song's artwork, so it reads as
/// something to play rather than a photo.
struct GridPlayBadge: View {
    var body: some View {
        Circle()
            .fill(Color.black.opacity(Constants.playBackdropOpacity))
            .frame(width: Constants.playSize, height: Constants.playSize)
            .overlay {
                IconKit.play
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white)
                    .frame(width: Constants.playGlyphSize, height: Constants.playGlyphSize)
            }
            .padding(Constants.playInset)
            .accessibilityHidden(true)
    }
}

#Preview("Play badge") {
    Color.accent
        .frame(width: Constants.previewWidth, height: Constants.previewWidth)
        .overlay(alignment: .bottomLeading) { GridPlayBadge() }
        .padding(.space16)
}

#Preview("Page and label") {
    GridWellSymbol(kind: "md", showsLabel: true) { _ in
        RoundedRectangle(cornerRadius: .size2)
            .fill(Color.white)
    }
    .frame(width: Constants.previewWidth, height: Constants.previewWidth)
    .background(Color.backgroundSecondary)
    .padding(.space16)
}
