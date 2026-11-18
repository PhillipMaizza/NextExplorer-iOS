import AppStorageKeys
import DesignSystem
import SwiftUI

private enum Constants {
    static let spacing: CGFloat = .space12
    static let denseSpacing: CGFloat = .space8
    static let textSpacing: CGFloat = .space2
    static let iconSize: CGFloat = .size32
    static let denseIconSize: CGFloat = .size24
    static let roomyIconSize: CGFloat = .size40
    static let padding: CGFloat = .space16
    static let densePadding: CGFloat = .space12
    static let minimumHeight: CGFloat = 112
    static let denseMinimumHeight: CGFloat = 88
    static let roomyMinimumHeight: CGFloat = 136
    static let cornerInset: CGFloat = .space12
    static let trailingSpacing: CGFloat = .space4
    static let selectionSize: CGFloat = .size24
    static let selectionRingWidth: CGFloat = 3
    static let hiddenOpacity: Double = 0.5
    static let fullOpacity: Double = 1
    static let previewWidth: CGFloat = 180
}

/// A folder in the grid: a roomy filled card with its glyph top leading, then the name and size,
/// and the favorite and offline marks (or the selection circle) in the top trailing corner.
struct FolderGridTile<Icon: View>: View {
    let name: String
    let isHidden: Bool
    let sizeText: String?
    var isFavorite = false
    var isAvailableOffline = false
    var isOpening = false
    var matchedSource: PreviewMatchedSource?
    @ViewBuilder let icon: () -> Icon
    @Environment(\.gridTileSelection) private var selection
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue

    private var size: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    private var iconSide: CGFloat {
        size.isDense ? Constants.denseIconSize : size.isRoomy ? Constants.roomyIconSize : Constants.iconSize
    }

    private var minimumHeight: CGFloat {
        size.isDense
            ? Constants.denseMinimumHeight
            : size.isRoomy ? Constants.roomyMinimumHeight : Constants.minimumHeight
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
        VStack(alignment: .leading, spacing: size.isDense ? Constants.denseSpacing : Constants.spacing) {
            icon()
                .frame(width: iconSide, height: iconSide)
                .opacity(isHidden ? Constants.hiddenOpacity : Constants.fullOpacity)
                .previewMatchedSource(matchedSource)
            VStack(alignment: .leading, spacing: Constants.textSpacing) {
                GridTileName(
                    name: name,
                    type: size.isDense ? .body3(.semibold) : .body2(.semibold),
                    style: selection.isHighlighted ? .link : isHidden ? .tertiary : .primaryOnSurface,
                    isFavorite: isFavorite
                )
                if let sizeText {
                    Text(sizeText)
                        .type(.caption(.regular), style: .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(size.isDense ? Constants.densePadding : Constants.padding)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background(Color.backgroundSecondary, in: shape)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: Constants.trailingSpacing) {
                if isAvailableOffline {
                    GridTileOfflineMark()
                }
                if isOpening {
                    DSSpinner()
                        .controlSize(.small)
                } else if selection.isSelecting {
                    DSSelectionIndicator(isSelected: selection.isSelected, size: Constants.selectionSize)
                }
            }
            .padding(Constants.cornerInset)
        }
        .overlay {
            shape.strokeBorder(Color.accent, lineWidth: Constants.selectionRingWidth)
                .opacity(selection.isHighlighted ? Constants.fullOpacity : 0)
        }
        .animation(DSMotion.selectModeStep, value: selection)
        .dsTapFlashHighlight()
    }
}

@MainActor
private func previewFolder(
    _ name: String,
    sizeText: String? = "1.2 GB",
    isFavorite: Bool = false,
    isAvailableOffline: Bool = false,
    isOpening: Bool = false
) -> some View {
    FolderGridTile(
        name: name,
        isHidden: name.hasPrefix("."),
        sizeText: sizeText,
        isFavorite: isFavorite,
        isAvailableOffline: isAvailableOffline,
        isOpening: isOpening
    ) {
        IconKit.folderFill
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.accent)
    }
    .frame(width: Constants.previewWidth)
}

#Preview("States") {
    VStack(spacing: .space12) {
        HStack(alignment: .top, spacing: .space12) {
            previewFolder("Documents")
            previewFolder("Photos", isFavorite: true, isAvailableOffline: true)
        }
        HStack(alignment: .top, spacing: .space12) {
            previewFolder("A folder with a name long enough to wrap", sizeText: nil)
            previewFolder(".config", isOpening: true)
        }
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}

#Preview("Select mode, dark") {
    HStack(alignment: .top, spacing: .space12) {
        previewFolder("Music")
            .dsGridTile(isSelecting: true, isSelected: false)
        previewFolder("Projects", isFavorite: true)
            .dsGridTile(isSelecting: true, isSelected: true)
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
    .preferredColorScheme(.dark)
}
