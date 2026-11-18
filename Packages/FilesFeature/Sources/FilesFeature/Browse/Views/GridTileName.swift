import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let glyphSize: CGFloat = .size20
    static let starSize: CGFloat = .size12
    static let nameSpacing: CGFloat = .space4
}

/// A grid tile's offline mark: the dotted arrow of the Offline tab, in accent, with a soft shadow so
/// it still reads over a picture.
struct GridTileOfflineMark: View {
    var body: some View {
        IconKit.availableOffline
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.accent)
            .frame(width: Constants.glyphSize, height: Constants.glyphSize)
            .elevation(.level1)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(L10n.Offline.badgeAvailable)
    }
}

/// A grid tile's name, with a small accent star after it when the item is a favorite.
struct GridTileName: View {
    let name: String
    let type: Typography.TextType
    let style: Typography.TextStyle
    let isFavorite: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.nameSpacing) {
            Text(name)
                .type(type, style: style)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
            if isFavorite {
                IconKit.starFill
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.starSize, height: Constants.starSize)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(L10n.Favorites.accessibilityBadge)
            }
        }
        .animation(DSMotion.pop, value: isFavorite)
    }
}

#Preview("Names") {
    VStack(alignment: .leading, spacing: .space12) {
        GridTileName(name: "Bills", type: .body2(.semibold), style: .primaryOnSurface, isFavorite: true)
        GridTileName(
            name: "A favorite with a name long enough to wrap",
            type: .body3(.semibold),
            style: .primaryOnSurface,
            isFavorite: true
        )
        .frame(width: 140, alignment: .leading)
        GridTileName(name: "Address Book", type: .body2(.semibold), style: .link, isFavorite: false)
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}

#Preview("Offline mark, dark") {
    GridTileOfflineMark()
        .padding(.space16)
        .background(Color.backgroundPrimary)
        .preferredColorScheme(.dark)
}
