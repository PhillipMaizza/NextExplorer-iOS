import SwiftUI

private enum Constants {
    static let previewTileWidth: CGFloat = 110
    static let previewIconSize: CGFloat = 56
    static let previewNames = ["Photos", "Documents", "notes.txt"]
}

/// What a grid tile's own content needs to draw select mode: the content decides where the accent
/// ring and the selection circle go (around a file's picture, around a whole folder card).
public struct GridTileSelection: Equatable, Sendable {
    public var isSelecting: Bool
    public var isSelected: Bool

    public init(isSelecting: Bool = false, isSelected: Bool = false) {
        self.isSelecting = isSelecting
        self.isSelected = isSelected
    }

    public var isHighlighted: Bool {
        isSelecting && isSelected
    }
}

public extension EnvironmentValues {
    @Entry var gridTileSelection = GridTileSelection()
}

public extension View {
    /// Lays content out as a borderless grid tile and hands its select mode state to the content
    /// through `gridTileSelection`, which rings what is picked.
    func dsGridTile(isSelecting: Bool = false, isSelected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
        let selection = GridTileSelection(isSelecting: isSelecting, isSelected: isSelected)
        return environment(\.gridTileSelection, selection)
            .frame(maxWidth: .infinity)
            .contentShape(shape)
        #if os(iOS)
            .contentShape(.contextMenuPreview, shape)
        #endif
            .accessibilityAddTraits(selection.isHighlighted ? .isSelected : [])
    }
}

private struct PreviewTile: View {
    let name: String
    @Environment(\.gridTileSelection) private var selection

    var body: some View {
        VStack(spacing: .space8) {
            IconKit.folderFill
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
                .frame(width: Constants.previewIconSize, height: Constants.previewIconSize)
            Text(name)
                .type(.body2(.semibold), style: selection.isHighlighted ? .link : .primaryOnSurface)
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
            .dsGridTile(isSelecting: true, isSelected: false)
        PreviewTile(name: Constants.previewNames[2])
            .dsGridTile(isSelecting: true, isSelected: true)
    }
    .frame(width: Constants.previewTileWidth * 3 + .space16 * 2)
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
