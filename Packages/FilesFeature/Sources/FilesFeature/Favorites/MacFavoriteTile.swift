#if os(macOS)
    import CoreModels
    import DesignSystem
    import SwiftUI

    struct MacFavoriteTile: View {
        let favorite: Favorite

        var body: some View {
            MacFolderTile(
                size: MacBrowseTableMetrics.tileSize,
                glyph: FavoriteIcon.symbol(for: favorite.icon),
                tint: FavoriteColor.resolve(favorite.color) ?? Color.accent
            )
            .symbolVariant(FavoriteIcon.isFilled(favorite.icon) ? .fill : .none)
        }
    }

    enum MacFavoritePreviewData {
        static let favorites = [
            Favorite(
                id: "1",
                path: "/Documents/Projects",
                label: "Projects",
                icon: "outline:StarIcon",
                color: nil,
                position: 0,
                createdAt: .distantPast,
                updatedAt: .distantPast
            ),
            Favorite(
                id: "2",
                path: "/Photos/2026",
                label: nil,
                icon: "solid:HeartIcon",
                color: "blue",
                position: 1,
                createdAt: .distantPast,
                updatedAt: .distantPast
            ),
        ]
    }

    #Preview("Favorite tiles") {
        HStack(spacing: .space16) {
            ForEach(MacFavoritePreviewData.favorites) { MacFavoriteTile(favorite: $0) }
        }
        .padding()
        .background(Color.macCard)
    }
#endif
