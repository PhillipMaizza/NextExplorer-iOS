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
    static let openingDimOpacity: Double = 0.45
    static let hiddenOpacity: Double = 0.5
    static let fullOpacity: Double = 1
    static let previewWidth: CGFloat = 120
    #if os(macOS)
        static let captionInset: CGFloat = .space4
    #elseif os(iOS)
        static let captionInset: CGFloat = .zero
    #endif
    /// Below this contrast ratio a well melts into the page, so it gets an outline.
    static let outlineContrastRatio: Double = 1.15
    static let luminanceOffset: Double = 0.05
    static let redWeight: Double = 0.2126
    static let greenWeight: Double = 0.7152
    static let blueWeight: Double = 0.0722
}

/// A file in the grid: a rounded picture well (the thumbnail, a page, or the kind chip for files with
/// nothing to show), then the name and its size. Select mode rings the well and shows the selection
/// circle in its corner.
struct FileGridTile<Picture: View>: View {
    let name: String
    let isHidden: Bool
    let sizeText: String?
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

    private var shouldShowOutline: Bool {
        // Only the colour scheme matters here; reading the whole environment would redraw every
        // tile on any change to it.
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        return Self.isLowContrast(
            Color.backgroundSecondary.resolve(in: environment),
            Color.backgroundPrimary.resolve(in: environment)
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
            // The name and its size read as one label, tighter than the gap under the well.
            VStack(alignment: .leading, spacing: 0) {
                GridTileName(
                    name: name,
                    type: isRoomy ? .body2(.semibold) : .body3(.semibold),
                    style: selection.isHighlighted ? .link : isHidden ? .tertiary : .primaryOnSurface,
                    isFavorite: isFavorite
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                caption
            }
            .padding(.horizontal, Constants.captionInset)
        }
        // The ring, the circle and the name's colour change in one step.
        .animation(DSMotion.selectModeStep, value: selection)
    }

    private var well: some View {
        let shape = RoundedRectangle(cornerRadius: Constants.wellRadius, style: .continuous)
        return Rectangle()
            .fill(Color.backgroundSecondary)
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
                if shouldShowOutline {
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
        isFavorite: isFavorite,
        isAvailableOffline: isAvailableOffline,
        isOpening: isOpening
    ) {
        FileKindChip(kind: kind)
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
        previewTile("setup.exe", kind: "exe")
            .dsGridTile(isSelecting: true, isSelected: false)
        previewTile("Budget.xlsx", kind: "xlsx", isFavorite: true)
            .dsGridTile(isSelecting: true, isSelected: true)
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
