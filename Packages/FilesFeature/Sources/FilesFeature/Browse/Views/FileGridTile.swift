import AppStorageKeys
import DesignSystem
import SwiftUI

private enum Constants {
    static let spacing: CGFloat = .size6
    static let wellRadius: CGFloat = .radiusMedium
    static let squareRatio: CGFloat = 1
    static let roomyRatio: CGFloat = 4.0 / 3.0
    static let overlayInset: CGFloat = .size6
    static let selectionSize: CGFloat = .size24
    static let selectionRingWidth: CGFloat = 3
    static let lightTintOpacity: Double = 0.14
    static let darkTintOpacity: Double = 0.22
    static let openingDimOpacity: Double = 0.45
    static let hiddenOpacity: Double = 0.5
    static let fullOpacity: Double = 1
    static let previewWidth: CGFloat = 120
    /// Below this contrast ratio a well melts into the page, so it gets an outline.
    static let outlineContrastRatio: Double = 1.15
    static let luminanceOffset: Double = 0.05
    static let redWeight: Double = 0.2126
    static let greenWeight: Double = 0.7152
    static let blueWeight: Double = 0.0722
}

/// A file in the grid: a rounded picture well (the thumbnail, or a tinted well with the type icon
/// for files with no picture), then the name and its size; the type icon carries the extension. Select mode rings the
/// well and shows the selection circle in its corner.
struct FileGridTile<Picture: View>: View {
    let name: String
    let isHidden: Bool
    let sizeText: String?
    /// The kind's colour for a file with no picture of its own; `nil` keeps the well neutral.
    let tint: Color?
    var isFavorite = false
    var isAvailableOffline = false
    var isOpening = false
    var matchedSource: PreviewMatchedSource?
    @ViewBuilder let picture: () -> Picture
    @Environment(\.gridTileSelection) private var selection
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue

    private var isRoomy: Bool {
        (ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium).isRoomy
    }

    private var wellFill: Color {
        guard let tint else { return .backgroundSecondary }
        return tint.opacity(colorScheme == .dark ? Constants.darkTintOpacity : Constants.lightTintOpacity)
    }

    private var needsOutline: Bool {
        // Only the colour scheme matters here; reading the whole environment would redraw every
        // tile on any change to it.
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        let page = Color.backgroundPrimary.resolve(in: environment)
        guard let tint else {
            return Self.isLowContrast(Color.backgroundSecondary.resolve(in: environment), page)
        }
        let opacity = Double(colorScheme == .dark ? Constants.darkTintOpacity : Constants.lightTintOpacity)
        return Self.isLowContrast(Self.composite(tint.resolve(in: environment), opacity: opacity, over: page), page)
    }

    /// A colour laid over another at `opacity`, in linear light as the screen mixes them.
    nonisolated static func composite(_ top: Color.Resolved, opacity: Double, over bottom: Color.Resolved) -> Color
        .Resolved
    {
        let alpha = Float(opacity) * top.opacity
        return Color.Resolved(
            colorSpace: .sRGBLinear,
            red: bottom.linearRed * (1 - alpha) + top.linearRed * alpha,
            green: bottom.linearGreen * (1 - alpha) + top.linearGreen * alpha,
            blue: bottom.linearBlue * (1 - alpha) + top.linearBlue * alpha
        )
    }

    /// Whether two colours sit too close in brightness to tell apart, by WCAG contrast ratio.
    nonisolated static func isLowContrast(_ first: Color.Resolved, _ second: Color.Resolved) -> Bool {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + Constants.luminanceOffset) / (darker + Constants.luminanceOffset)
            < Constants.outlineContrastRatio
    }

    private nonisolated static func luminance(_ color: Color.Resolved) -> Double {
        Constants.redWeight * Double(color.linearRed)
            + Constants.greenWeight * Double(color.linearGreen)
            + Constants.blueWeight * Double(color.linearBlue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacing) {
            well
            GridTileName(
                name: name,
                type: isRoomy ? .body2(.semibold) : .body3(.semibold),
                style: selection.isHighlighted ? .link : isHidden ? .tertiary : .primaryOnSurface,
                isFavorite: isFavorite
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            caption
        }
        // The ring, the circle and the name's colour change in one step.
        .animation(DSMotion.selectModeStep, value: selection)
    }

    private var well: some View {
        let shape = RoundedRectangle(cornerRadius: Constants.wellRadius, style: .continuous)
        return Rectangle()
            .fill(wellFill)
            .aspectRatio(isRoomy ? Constants.roomyRatio : Constants.squareRatio, contentMode: .fit)
            .overlay {
                picture()
                    .opacity(isHidden ? Constants.hiddenOpacity : Constants.fullOpacity)
            }
            .overlay {
                if isOpening {
                    Color.black.opacity(Constants.openingDimOpacity)
                    DSSpinner()
                        .controlSize(.small)
                }
            }
            .clipShape(shape)
            .previewMatchedSource(matchedSource)
            .overlay(alignment: .topTrailing) {
                if isAvailableOffline {
                    GridTileOfflineMark()
                        .padding(Constants.overlayInset)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if selection.isSelecting {
                    DSSelectionIndicator(isSelected: selection.isSelected, size: Constants.selectionSize)
                        .background(Circle().fill(Color.backgroundPrimary))
                        .padding(Constants.overlayInset)
                }
            }
            .overlay {
                if needsOutline {
                    shape.strokeBorder(Color.borderPrimary, lineWidth: .borderWidthHairline)
                }
            }
            .overlay {
                shape.strokeBorder(Color.accent, lineWidth: Constants.selectionRingWidth)
                    .opacity(selection.isHighlighted ? Constants.fullOpacity : 0)
            }
            .dsTapFlashHighlight(cornerRadius: Constants.wellRadius)
    }

    private var caption: some View {
        Text(sizeText ?? "")
            .type(.caption(.regular), style: .secondary)
            .lineLimit(1)
    }
}

/// The type icon centred in a well that has no picture: the same page size and slim banner as a
/// text file's page of its own lines, so every file in the grid reads as one sheet.
struct GridWellTypeIcon: View {
    /// A page's side as a share of the well's shorter side.
    static let pageFraction: CGFloat = 0.5

    let kind: String

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * Self.pageFraction
            FileTypeIcon(kind: kind, bannerHeightFraction: FileTypeBanner.slimHeightFraction)
                .frame(width: side, height: side)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

@MainActor
private func previewTile(
    _ name: String,
    kind: String = "pdf",
    isFavorite: Bool = false,
    isAvailableOffline: Bool = false,
    isOpening: Bool = false
) -> some View {
    FileGridTile(
        name: name,
        isHidden: name.hasPrefix("."),
        sizeText: "3.2 MB",
        tint: FileTypeIcon.tint(forKind: kind),
        isFavorite: isFavorite,
        isAvailableOffline: isAvailableOffline,
        isOpening: isOpening
    ) {
        GridWellTypeIcon(kind: kind)
    }
    .frame(width: Constants.previewWidth)
}

#Preview("States") {
    HStack(alignment: .top, spacing: .space12) {
        previewTile("Report.pdf")
        previewTile("Holiday.mov", kind: "mov", isFavorite: true, isAvailableOffline: true)
        previewTile("A very long file name that wraps over two lines.zip", kind: "zip")
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}

#Preview("Hidden and opening, dark") {
    HStack(alignment: .top, spacing: .space12) {
        previewTile(".env", kind: "env")
        previewTile("Song.mp3", kind: "mp3", isOpening: true)
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Select mode") {
    HStack(alignment: .top, spacing: .space12) {
        previewTile("Notes.txt", kind: "txt")
            .dsGridTile(isSelecting: true, isSelected: false)
        previewTile("Budget.xlsx", kind: "xlsx", isFavorite: true)
            .dsGridTile(isSelecting: true, isSelected: true)
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
