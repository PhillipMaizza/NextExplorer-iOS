import AppStorageKeys
import CoreModels
import DesignSystem
import Localization
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
    let thumbnailSignature: String
    let serverURL: URL?
    let showThumbnails: Bool
    let iconSize: CGFloat
    /// The full item, when built from one — needed for the on device PDF first page render,
    /// which fetches the file through `filesClient.previewFileLowPriority`.
    private let file: FileItem?
    /// Favorites grid: a favorite's custom icon, weight + colour in place of the folder glyph.
    var customIcon: Image?
    var customIconTint: Color?
    var customIconFilled: Bool
    /// When set, the icon/thumbnail is the source the preview cover's `.zoom` transition
    /// grows from and shrinks back to.
    var matchedSource: PreviewMatchedSource?
    /// True while this file's content is downloading after a tap — a small spinner sits in the
    /// cell's bottom-trailing corner (not over the icon) and the preview holds off until ready.
    var isOpening: Bool = false
    var isAvailableOffline: Bool = false
    @AppStorage(AppStorageKeys.showFilenameExtensions) private var showFilenameExtensions = true

    /// `thumbnailFile` opts a caller with only a name/kind (a search hit) into the same thumbnail
    /// rendering a browse tile gets. Server thumbnails still need the file to report
    /// `supportsThumbnail`; the on device PDF render only needs its kind.
    init(
        name: String,
        isDirectory: Bool,
        isFavorite: Bool = false,
        kind: String? = nil,
        thumbnailFile: FileItem? = nil,
        serverURL: URL? = nil,
        showThumbnails: Bool = false,
        iconSize: CGFloat = Constants.defaultIconSize,
        customIcon: Image? = nil,
        customIconTint: Color? = nil,
        customIconFilled: Bool = false,
        matchedSource: PreviewMatchedSource? = nil,
        isOpening: Bool = false,
        isAvailableOffline: Bool = false
    ) {
        self.name = name
        self.isDirectory = isDirectory
        self.isAvailableOffline = isAvailableOffline
        self.isFavorite = isFavorite
        itemID = thumbnailFile?.id
        self.kind = kind
        supportsThumbnail = thumbnailFile?.supportsThumbnail ?? false
        thumbnailSignature = thumbnailFile?.cacheSignature ?? ""
        self.serverURL = serverURL
        self.showThumbnails = showThumbnails
        self.iconSize = iconSize
        file = thumbnailFile
        self.customIcon = customIcon
        self.customIconTint = customIconTint
        self.customIconFilled = customIconFilled
        self.matchedSource = matchedSource
        self.isOpening = isOpening
    }

    init(item: FileItem, isFavorite: Bool = false, serverURL: URL? = nil, showThumbnails: Bool = false, iconSize: CGFloat = Constants.defaultIconSize, matchedSource: PreviewMatchedSource? = nil, isOpening: Bool = false, isAvailableOffline: Bool = false) {
        self.isAvailableOffline = isAvailableOffline
        name = item.name
        isDirectory = item.isDirectory
        self.isFavorite = isFavorite
        itemID = item.id
        kind = item.kind
        supportsThumbnail = item.supportsThumbnail
        thumbnailSignature = item.cacheSignature
        self.serverURL = serverURL
        self.showThumbnails = showThumbnails
        self.iconSize = iconSize
        file = item
        customIcon = nil
        customIconTint = nil
        customIconFilled = false
        self.matchedSource = matchedSource
        self.isOpening = isOpening
    }

    private var isHidden: Bool {
        isHiddenFileName(name)
    }

    private var displayName: String {
        displayFileName(name, isDirectory: isDirectory, showExtension: showFilenameExtensions)
    }

    private var isEligibleForThumbnail: Bool {
        !isDirectory && supportsThumbnail && showThumbnails && serverURL != nil && itemID != nil
    }

    private var isEligibleForPDFThumbnail: Bool {
        showThumbnails && serverURL != nil && (file?.isPDF ?? false)
    }

    var body: some View {
        VStack(spacing: Constants.cellSpacing) {
            icon
                .opacity(isHidden ? Constants.halfOpacity : Constants.fullOpacity)
                .previewMatchedSource(matchedSource)
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
                                    .shadow(radius: Constants.favoriteBadgeShadowRadius)
                            )
                            .symbolEffect(.bounce, value: isFavorite)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel(L10n.Favorites.accessibilityBadge)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isAvailableOffline {
                        IconKit.download
                            .resizable()
                            .scaledToFit()
                            .symbolVariant(.fill)
                            .foregroundStyle(Color.accent)
                            .frame(width: Constants.favoriteBadgeSize, height: Constants.favoriteBadgeSize)
                            .padding(Constants.favoriteBadgePadding)
                            .background(
                                Circle()
                                    .fill(Color.backgroundPrimary)
                                    .frame(width: Constants.favoriteBadgeBackgroundSize, height: Constants.favoriteBadgeBackgroundSize)
                                    .shadow(radius: Constants.favoriteBadgeShadowRadius)
                            )
                            .symbolEffect(.bounce, value: isAvailableOffline)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel(L10n.Offline.badgeAvailable)
                    }
                }
                .animation(.spring(response: Constants.favoriteSpringResponse, dampingFraction: Constants.favoriteSpringDamping), value: isFavorite)
                .animation(.spring(response: Constants.favoriteSpringResponse, dampingFraction: Constants.favoriteSpringDamping), value: isAvailableOffline)
                // Only favoriting buzzes — un-favoriting isn't a "win" worth celebrating the same way.
                .hapticFeedback(.success, trigger: isFavorite) { _, isFavorite in isFavorite }
            Text(displayName)
                .type(.body2(.semibold), style: isHidden ? .tertiary : .primaryOnSurface)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if isOpening {
                DSSpinner()
                    .controlSize(.small)
                    .padding(Constants.favoriteBadgePadding)
                    .background(Circle().fill(Color.backgroundPrimary).shadow(radius: Constants.favoriteBadgeShadowRadius))
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let customIcon {
            customIcon
                .resizable()
                .scaledToFit()
                .symbolVariant(customIconFilled ? .fill : .none)
                .foregroundStyle(customIconTint ?? Color.accent)
                .frame(width: iconSize, height: iconSize)
        } else if isEligibleForThumbnail, let serverURL, let itemID {
            ThumbnailImage(serverURL: serverURL, path: itemID, signature: thumbnailSignature, fallbackIcon: IconKit.document, iconTint: Color.secondaryDS)
                .frame(width: iconSize, height: iconSize)
        } else if isEligibleForPDFThumbnail, let serverURL, let file {
            PDFThumbnailImage(serverURL: serverURL, item: file)
                .frame(width: iconSize, height: iconSize)
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
