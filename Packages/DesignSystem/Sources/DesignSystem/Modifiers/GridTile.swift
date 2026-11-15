import SwiftUI

private enum Constants {
    static let borderWidth: CGFloat = 1
    static let selectedBorderWidth: CGFloat = 2
    /// A picked tile's soft accent wash, so the selection reads from the fill as well as the outline.
    static let selectedFillOpacity: Double = 0.12
    static let previewTileWidth: CGFloat = 110
    static let previewIconSize: CGFloat = 56
    static let previewNames = ["Photos", "Documents", "notes.txt"]
}

/// A file grid tile: a thin outline rather than a filled card, so a screen of tiles stays light. In
/// select mode the tiles wiggle, as apps do on the Home Screen when they can be moved, and a picked
/// tile draws its outline in the accent over a soft accent wash.
private struct GridTileModifier: ViewModifier {
    let padding: CGFloat
    let isSelecting: Bool
    let isSelected: Bool
    /// Neighbouring tiles tilt opposite ways, so the grid does not swing as one block.
    let tiltsLeftFirst: Bool
    @Environment(\.selectionIndicatorsShown) private var indicatorsShown
    @State private var tilt: Double = 0

    init(padding: CGFloat, isSelecting: Bool, isSelected: Bool, seed: String) {
        self.padding = padding
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        tiltsLeftFirst = seed.utf8.reduce(0) { $0 &+ Int($1) }.isMultiple(of: 2)
    }

    /// Follows the screen's select mode chrome when there is one, so the wiggle starts and stops in
    /// the same step as the rest of select mode, both ways.
    private var isWiggling: Bool {
        indicatorsShown ?? isSelecting
    }

    private var isHighlighted: Bool {
        isSelecting && isSelected
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background {
                shape.fill(Color.accent.opacity(isHighlighted ? Constants.selectedFillOpacity : 0))
                    .animation(DSMotion.selectModeStep, value: isHighlighted)
            }
            .contentShape(shape)
        #if os(iOS)
            .contentShape(.contextMenuPreview, shape)
        #endif
            .overlay {
                shape.strokeBorder(
                    isHighlighted ? Color.accent : Color.borderPrimary,
                    lineWidth: isHighlighted ? Constants.selectedBorderWidth : Constants.borderWidth
                )
                .animation(DSMotion.selectModeStep, value: isHighlighted)
            }
            .rotationEffect(.degrees(tilt))
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
            .onAppear { updateWiggle(isWiggling) }
            .onChange(of: isWiggling) { _, isWiggling in updateWiggle(isWiggling) }
    }

    private func updateWiggle(_ isOn: Bool) {
        guard isOn, let wiggle = DSMotion.selectModeWiggle else {
            // Outside select mode a tile appearing already rests level: nothing to animate.
            if tilt != 0 {
                withAnimation(DSMotion.selectModeStep) { tilt = 0 }
            }
            return
        }
        let angle = DSMotion.selectModeWiggleAngle
        tilt = tiltsLeftFirst ? angle : -angle
        withAnimation(wiggle) { tilt = tiltsLeftFirst ? -angle : angle }
    }
}

public extension View {
    /// Lays content out as a grid tile, outlined, wiggling while selecting and washed and outlined in
    /// the accent once picked. `seed` (the item's id) decides which way the tile tilts first.
    func dsGridTile(
        padding: CGFloat = .space12,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        seed: String = ""
    ) -> some View {
        modifier(GridTileModifier(padding: padding, isSelecting: isSelecting, isSelected: isSelected, seed: seed))
    }
}

private struct PreviewTile: View {
    let name: String

    var body: some View {
        VStack(spacing: .space8) {
            IconKit.folderFill
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
                .frame(width: Constants.previewIconSize, height: Constants.previewIconSize)
            Text(name)
                .type(.body2(.semibold), style: .primaryOnSurface)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview("Tiles") {
    HStack(spacing: .space16) {
        PreviewTile(name: Constants.previewNames[0])
            .dsGridTile()
        PreviewTile(name: Constants.previewNames[1])
            .dsGridTile(isSelecting: true, isSelected: false, seed: Constants.previewNames[1])
        PreviewTile(name: Constants.previewNames[2])
            .dsGridTile(isSelecting: true, isSelected: true, seed: Constants.previewNames[2])
    }
    .frame(width: Constants.previewTileWidth * 3 + .space16 * 2)
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
