import AppStorageKeys
import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let previewWidth: CGFloat = 120
    static let previewFolderWidth: CGFloat = 180
}

/// One tile of a file grid (Browse, Favorites, Offline, search): a `FolderGridTile` card for a folder,
/// a `FileGridTile` picture well for a file, with the same information `FileRowView` shows in a list.
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
    /// A file's size, or a folder's counted size; `nil` shows no size.
    let size: Int64?
    /// Shown under the name in place of the size, such as a favorite's location.
    var subtitle: String?
    /// The full item, when built from one: needed for the on device document first page render,
    /// which fetches the file through `filesClient.previewFileLowPriority`.
    private let file: FileItem?
    /// Favorites grid: a favorite's custom icon, weight + colour in place of the folder glyph.
    var customIcon: Image?
    var customIconTint: Color?
    var isCustomIconFilled: Bool
    /// When set, the picture is the source the preview cover's `.zoom` transition grows from and
    /// shrinks back to.
    var matchedSource: PreviewMatchedSource?
    /// True while this file's content is downloading after a tap: the well dims under a spinner and
    /// the preview holds off until ready.
    var isOpening: Bool = false
    var isAvailableOffline: Bool = false
    /// Shown in place of an unknown size, as a list row does.
    private let dateModified: Date?
    @AppStorage(AppStorageKeys.showFilenameExtensions) private var shouldShowFilenameExtensions = true
    @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue

    /// `thumbnailFile` opts a caller with only a name/kind (a search hit) into the same thumbnail
    /// rendering a browse tile gets. Server thumbnails still need the file to report
    /// `supportsThumbnail`; the on device document render needs its kind and size.
    init(
        name: String,
        isDirectory: Bool,
        isFavorite: Bool = false,
        kind: String? = nil,
        size: Int64? = nil,
        thumbnailFile: FileItem? = nil,
        serverURL: URL? = nil,
        showThumbnails: Bool = false,
        customIcon: Image? = nil,
        customIconTint: Color? = nil,
        isCustomIconFilled: Bool = false,
        matchedSource: PreviewMatchedSource? = nil,
        isOpening: Bool = false,
        isAvailableOffline: Bool = false,
        subtitle: String? = nil
    ) {
        self.subtitle = subtitle
        self.name = name
        self.isDirectory = isDirectory
        self.isAvailableOffline = isAvailableOffline
        self.isFavorite = isFavorite
        itemID = thumbnailFile?.id
        self.kind = kind
        self.size = size ?? (isDirectory ? nil : thumbnailFile?.size)
        supportsThumbnail = thumbnailFile?.supportsThumbnail ?? false
        thumbnailSignature = thumbnailFile?.cacheSignature ?? ""
        self.serverURL = serverURL
        self.showThumbnails = showThumbnails
        file = thumbnailFile
        dateModified = thumbnailFile.flatMap { $0.hasKnownDate ? $0.dateModified : nil }
        self.customIcon = customIcon
        self.customIconTint = customIconTint
        self.isCustomIconFilled = isCustomIconFilled
        self.matchedSource = matchedSource
        self.isOpening = isOpening
    }

    init(
        item: FileItem,
        isFavorite: Bool = false,
        serverURL: URL? = nil,
        showThumbnails: Bool = false,
        folderSize: Int64? = nil,
        matchedSource: PreviewMatchedSource? = nil,
        isOpening: Bool = false,
        isAvailableOffline: Bool = false
    ) {
        self.isAvailableOffline = isAvailableOffline
        name = item.name
        isDirectory = item.isDirectory
        self.isFavorite = isFavorite
        itemID = item.id
        kind = item.kind
        size = item.isDirectory ? folderSize : item.size
        supportsThumbnail = item.supportsThumbnail
        thumbnailSignature = item.cacheSignature
        self.serverURL = serverURL
        self.showThumbnails = showThumbnails
        file = item
        dateModified = item.hasKnownDate ? item.dateModified : nil
        customIcon = nil
        customIconTint = nil
        isCustomIconFilled = false
        self.matchedSource = matchedSource
        self.isOpening = isOpening
    }

    private var isHidden: Bool {
        isHiddenFileName(name)
    }

    private var displayName: String {
        displayFileName(name, isDirectory: isDirectory, showExtension: shouldShowFilenameExtensions)
    }

    private var sizeText: String? {
        if let subtitle {
            return subtitle
        }
        if let size {
            return FileSizeFormat.string(size)
        }
        return dateModified.map { (DateDisplayFormat(rawValue: dateFormatRaw) ?? .system).string(
            from: $0,
            includeTime: false
        ) }
    }

    private var isEligibleForThumbnail: Bool {
        !isDirectory && (supportsThumbnail || shouldReadOwnContent) && showThumbnails && serverURL != nil && itemID !=
            nil
    }

    /// Audio (cover art) and text (its first lines) have no server thumbnail: the app draws their own.
    private var shouldReadOwnContent: Bool {
        kind.map(ThumbnailImage.shouldReadOwnContent) ?? false
    }

    private var isEligibleForDocumentThumbnail: Bool {
        showThumbnails && serverURL != nil && file.map(DocumentThumbnailStore.isEligible) == true
    }

    var body: some View {
        if isDirectory {
            FolderGridTile(
                name: displayName,
                isHidden: isHidden,
                sizeText: sizeText,
                isFavorite: isFavorite,
                isAvailableOffline: isAvailableOffline,
                isOpening: isOpening,
                matchedSource: matchedSource
            ) {
                folderIcon
            }
        } else {
            FileGridTile(
                name: displayName,
                isHidden: isHidden,
                sizeText: sizeText,
                isFavorite: isFavorite,
                isAvailableOffline: isAvailableOffline,
                isOpening: isOpening,
                matchedSource: matchedSource
            ) {
                picture
            }
        }
    }

    @ViewBuilder
    private var folderIcon: some View {
        if let customIcon {
            customIcon
                .resizable()
                .scaledToFit()
                .symbolVariant(isCustomIconFilled ? .fill : .none)
                .foregroundStyle(customIconTint ?? Color.accent)
        } else {
            IconKit.folderFill
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
        }
    }

    @ViewBuilder
    private var picture: some View {
        if isEligibleForThumbnail, let serverURL, let itemID {
            ThumbnailImage(
                serverURL: serverURL, path: itemID, signature: thumbnailSignature, fallbackIcon: IconKit.document,
                iconTint: Color.secondaryDS,
                fileSize: file?.size, modified: file?.dateModified,
                isGridWell: true
            )
        } else if isEligibleForDocumentThumbnail, let serverURL, let file {
            DocumentThumbnailImage(serverURL: serverURL, item: file, isGridWell: true) {
                FileKindChip(kind: file.kind)
            }
        } else {
            FileKindChip(kind: kind ?? "")
        }
    }
}

#Preview("Folders") {
    HStack(alignment: .top, spacing: .space12) {
        GridCellView(name: "Photos", isDirectory: true, size: 2_400_000_000)
        GridCellView(name: "Documents", isDirectory: true, isFavorite: true, isAvailableOffline: true)
    }
    .frame(width: Constants.previewFolderWidth * 2 + .space12)
    .padding(.space16)
    .background(Color.backgroundPrimary)
}

#Preview("Files") {
    HStack(alignment: .top, spacing: .space12) {
        GridCellView(name: "vacation.jpg", isDirectory: false, kind: "jpg", size: 2_400_000)
        GridCellView(name: "report.pdf", isDirectory: false, isFavorite: true, kind: "pdf", size: 180_000)
        GridCellView(name: "A very long file name that should wrap.zip", isDirectory: false, kind: "zip")
    }
    .frame(width: Constants.previewWidth * 3 + .space12 * 2)
    .padding(.space16)
    .background(Color.backgroundPrimary)
}

#Preview("Hidden, dark") {
    HStack(alignment: .top, spacing: .space12) {
        GridCellView(name: ".config", isDirectory: true)
        GridCellView(name: ".env", isDirectory: false, kind: "env", size: 120)
    }
    .frame(width: Constants.previewFolderWidth + Constants.previewWidth + .space12)
    .padding(.space16)
    .background(Color.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Thumbnails on") {
    // `.previewValue`'s `thumbnailURL` always resolves to `nil`, so this renders the fallback icon
    // on a neutral well: it documents the code path rather than showing a picture.
    GridCellView(
        item: FileItem(
            name: "vacation.jpg",
            path: "",
            dateModified: Date(),
            size: 2_400_000,
            kind: "jpg",
            supportsThumbnail: true
        ),
        serverURL: URL(string: "https://nextexplorer.example.com"),
        showThumbnails: true
    )
    .frame(width: Constants.previewWidth)
    .padding(.space16)
}

#Preview("Select mode tiles") {
    HStack(alignment: .top, spacing: .space12) {
        GridCellView(name: "Photos", isDirectory: true)
            .dsGridTile(isSelecting: true, isSelected: false)
            .frame(width: Constants.previewFolderWidth)
        GridCellView(name: "vacation.jpg", isDirectory: false, kind: "jpg")
            .dsGridTile(isSelecting: true, isSelected: true)
            .frame(width: Constants.previewWidth)
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
