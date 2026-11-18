import AppStorageKeys
import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let pdfInset: CGFloat = .space8
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
    /// The full item, when built from one: needed for the on device PDF first page render,
    /// which fetches the file through `filesClient.previewFileLowPriority`.
    private let file: FileItem?
    /// Favorites grid: a favorite's custom icon, weight + colour in place of the folder glyph.
    var customIcon: Image?
    var customIconTint: Color?
    var customIconFilled: Bool
    /// When set, the picture is the source the preview cover's `.zoom` transition grows from and
    /// shrinks back to.
    var matchedSource: PreviewMatchedSource?
    /// True while this file's content is downloading after a tap: the well dims under a spinner and
    /// the preview holds off until ready.
    var isOpening: Bool = false
    var isAvailableOffline: Bool = false
    @AppStorage(AppStorageKeys.showFilenameExtensions) private var shouldShowFilenameExtensions = true

    /// `thumbnailFile` opts a caller with only a name/kind (a search hit) into the same thumbnail
    /// rendering a browse tile gets. Server thumbnails still need the file to report
    /// `supportsThumbnail`; the on device PDF render only needs its kind.
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
        customIconFilled: Bool = false,
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
        self.customIcon = customIcon
        self.customIconTint = customIconTint
        self.customIconFilled = customIconFilled
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
        displayFileName(name, isDirectory: isDirectory, showExtension: shouldShowFilenameExtensions)
    }

    private var sizeText: String? {
        subtitle ?? size.map { FileSizeFormat.string($0) }
    }

    private var isEligibleForThumbnail: Bool {
        !isDirectory && (supportsThumbnail || readsOwnContent) && showThumbnails && serverURL != nil && itemID != nil
    }

    /// Audio (cover art) and text (its first lines) have no server thumbnail: the app draws their own.
    private var readsOwnContent: Bool {
        kind.map(ThumbnailImage.readsOwnContent) ?? false
    }

    private var isEligibleForPDFThumbnail: Bool {
        showThumbnails && serverURL != nil && (file?.isPDF ?? false)
    }

    /// Only a file with no picture of its own takes its kind's colour; pictures sit on a neutral well.
    private var wellTint: Color? {
        guard !isEligibleForThumbnail, !isEligibleForPDFThumbnail, let kind else { return nil }
        return FileTypeIcon.tint(forKind: kind)
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
                tint: wellTint,
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
                .symbolVariant(customIconFilled ? .fill : .none)
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
            GeometryReader { proxy in
                // A text file draws a page of its own lines: it sits inside the well like a sheet.
                let pageSide = min(proxy.size.width, proxy.size.height) * GridWellTypeIcon.pageFraction
                let isPage = kind.map(TextSnippet.isTextKind) ?? false
                ThumbnailImage(
                    serverURL: serverURL, path: itemID, signature: thumbnailSignature, fallbackIcon: IconKit.document,
                    fallbackKind: kind,
                    fallbackBannerFraction: FileTypeBanner.slimHeightFraction,
                    iconTint: Color.secondaryDS,
                    fallbackSize: pageSide,
                    fileSize: file?.size, modified: file?.dateModified,
                    fillsFrame: !isPage
                )
                .frame(width: isPage ? pageSide : proxy.size.width, height: isPage ? pageSide : proxy.size.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else if isEligibleForPDFThumbnail, let serverURL, let file {
            PDFThumbnailImage(serverURL: serverURL, item: file)
                .padding(Constants.pdfInset)
        } else {
            GridWellTypeIcon(kind: kind ?? "")
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
