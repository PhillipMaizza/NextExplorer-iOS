import DesignSystem
import SwiftUI

private enum Constants {
    static let cellSpacing: CGFloat = .space8
    static let iconSize: CGFloat = .iconLarge
    static let favoriteBadgeSize: CGFloat = .iconXSmall
    static let favoriteBadgePadding: CGFloat = .space2
    static let favoriteBadgeBackgroundSize: CGFloat = .size20
    static let favoriteBadgeShadowRadius: CGFloat = 0.5
    static let fullOpacity: Double = 1.0
    static let halfOpacity: Double = 0.5
}

/// One tile of `BrowseContentView`'s grid display mode: icon (dimmed if hidden, badged if
/// favorited) over a name, matching `FileRowView`'s list-mode information at a glance.
struct GridCellView: View {
    let name: String
    let isDirectory: Bool
    let isFavorite: Bool

    init(name: String, isDirectory: Bool, isFavorite: Bool = false) {
        self.name = name
        self.isDirectory = isDirectory
        self.isFavorite = isFavorite
    }

    private var isHidden: Bool { isHiddenFileName(name) }

    var body: some View {
        VStack(spacing: Constants.cellSpacing) {
            (isDirectory ? IconKit.folderFill : IconKit.document)
                .resizable()
                .scaledToFit()
                .foregroundStyle(isDirectory ? Color.accent : Color.secondaryDS)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .opacity(isHidden ? Constants.halfOpacity : Constants.fullOpacity)
                .overlay(alignment: .topTrailing) {
                    if isFavorite {
                        IconKit.starFill
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.accent)
                            .frame(width: Constants.favoriteBadgeSize, height: Constants.favoriteBadgeSize)
                            .padding(Constants.favoriteBadgePadding)
                            .background(
                                Circle()
                                    .fill(Color.backgroundPrimary)
                                    .frame(width: Constants.favoriteBadgeBackgroundSize, height: Constants.favoriteBadgeBackgroundSize)
                                    .shadow(radius: Constants.favoriteBadgeShadowRadius))
                    }
                }
            Text(name)
                .type(.body2(.semibold), style: isHidden ? .tertiary : .primary(for: .label))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Directory") {
    GridCellView(name: "Photos", isDirectory: true)
}

#Preview("File") {
    GridCellView(name: "vacation.jpg", isDirectory: false)
}

#Preview("Favorited directory") {
    GridCellView(name: "Documents", isDirectory: true, isFavorite: true)
}

#Preview("Hidden directory") {
    GridCellView(name: ".config", isDirectory: true)
}

#Preview("Hidden file") {
    GridCellView(name: ".env", isDirectory: false)
}

#Preview("Long name wraps to two lines") {
    GridCellView(name: "A very long file name that should wrap.pdf", isDirectory: false)
}

#Preview("All variants") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: .space16) {
        GridCellView(name: "Photos", isDirectory: true)
        GridCellView(name: "Documents", isDirectory: true, isFavorite: true)
        GridCellView(name: "vacation.jpg", isDirectory: false)
        GridCellView(name: ".hidden", isDirectory: true)
        GridCellView(name: ".hidden", isDirectory: false)
    }
    .padding(.space16)
}
