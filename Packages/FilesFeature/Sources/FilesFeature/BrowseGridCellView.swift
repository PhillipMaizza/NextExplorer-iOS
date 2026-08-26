import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let cellSpacing: CGFloat = .space8
    static let defaultIconSize: CGFloat = .iconLarge
    static let favoriteBadgeSize: CGFloat = .iconXSmall
    static let favoriteBadgePadding: CGFloat = .space2
    static let favoriteBadgeBackgroundSize: CGFloat = .size20
    static let favoriteBadgeShadowRadius: CGFloat = 0.5
    static let fullOpacity: Double = 1.0
    static let halfOpacity: Double = 0.5
    static let favoriteSpringResponse: Double = 0.3
    static let favoriteSpringDamping: Double = 0.7
}

/// One tile of `BrowseContentView`'s grid display mode: icon (dimmed if hidden, badged if
/// favorited) over a name, matching `FileRowView`'s list-mode information at a glance.
struct GridCellView: View {
    let name: String
    let isDirectory: Bool
    let isFavorite: Bool
    let itemID: String?
    let kind: String?
    let supportsThumbnail: Bool
    let serverURL: URL?
    let showThumbnails: Bool
    let iconSize: CGFloat

    init(name: String, isDirectory: Bool, isFavorite: Bool = false, kind: String? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.isFavorite = isFavorite
        self.itemID = nil
        self.kind = kind
        self.supportsThumbnail = false
        self.serverURL = nil
        self.showThumbnails = false
        self.iconSize = Constants.defaultIconSize
    }

    init(item: FileItem, isFavorite: Bool = false, serverURL: URL? = nil, showThumbnails: Bool = false, iconSize: CGFloat = Constants.defaultIconSize) {
        self.name = item.name
        self.isDirectory = item.isDirectory
        self.isFavorite = isFavorite
        self.itemID = item.id
        self.kind = item.kind
        self.supportsThumbnail = item.supportsThumbnail
        self.serverURL = serverURL
        self.showThumbnails = showThumbnails
        self.iconSize = iconSize
    }

    private var isHidden: Bool { isHiddenFileName(name) }

    private var isEligibleForThumbnail: Bool {
        !isDirectory && supportsThumbnail && showThumbnails && serverURL != nil && itemID != nil
    }

    var body: some View {
        VStack(spacing: Constants.cellSpacing) {
            icon
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
                            .symbolEffect(.bounce, value: isFavorite)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: Constants.favoriteSpringResponse, dampingFraction: Constants.favoriteSpringDamping), value: isFavorite)
                // Only favoriting buzzes — un-favoriting isn't a "win" worth celebrating the same way.
                .hapticFeedback(.success, trigger: isFavorite) { _, isFavorite in isFavorite }
            Text(name)
                .type(.body2(.semibold), style: isHidden ? .tertiary : .primary(for: .label))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var icon: some View {
        if isEligibleForThumbnail, let serverURL, let itemID {
            ThumbnailImage(serverURL: serverURL, path: itemID, fallbackIcon: IconKit.document, iconTint: Color.secondaryDS)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: .radiusControl))
        } else if isDirectory {
            IconKit.folderFill
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
                .frame(width: iconSize, height: iconSize)
        } else {
            FileTypeIcon(kind: kind ?? "")
                .frame(width: iconSize, height: iconSize)
        }
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

#Preview("Thumbnails on") {
    // `.previewValue`'s `thumbnailURL` always resolves to `nil`, so this renders the same
    // fallback icon as any other file — it documents/exercises the code path rather than
    // showing an actual image.
    GridCellView(
        item: FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg", supportsThumbnail: true),
        serverURL: URL(string: "https://nextexplorer.example.com"),
        showThumbnails: true
    )
}

#Preview("Thumbnails off (falls back to the plain icon even though the file supports one)") {
    GridCellView(
        item: FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg", supportsThumbnail: true),
        serverURL: URL(string: "https://nextexplorer.example.com"),
        showThumbnails: false
    )
}

#Preview("Thumbnail sizes: small, medium, large") {
    VStack(spacing: .space24) {
        ForEach(ThumbnailSize.allCases) { size in
            GridCellView(
                item: FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg"),
                iconSize: size.iconSize
            )
        }
    }
    .padding(.space16)
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
