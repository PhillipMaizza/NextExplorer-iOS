import AppStorageKeys
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconFrame: CGFloat = .iconMedium
    static let chevronSize: CGFloat = .iconXSmall
    static let fullOpacity: Double = 1.0
    static let halfOpacity: Double = 0.5
}

struct FileRowView: View {
    let name: String
    let isDirectory: Bool
    let dateModified: Date?
    let size: Int64?
    let customSubtitle: String?
    /// Whether the name and subtitle wrap instead of being cut to one line each: where the row's
    /// details matter more than an even list (the trash).
    var shouldWrapText = false
    /// A small semibold line rendered under the subtitle, e.g. "Line 58" for a search content
    /// match. `nil` hides it.
    let lineLabel: String?
    let isFavorite: Bool
    let itemID: String?
    let kind: String?
    let supportsThumbnail: Bool
    let thumbnailSignature: String
    let serverURL: URL?
    let shouldShowThumbnails: Bool
    /// The full item, when built from one: needed for the on device document first page render,
    /// which fetches the file through `filesClient.previewFileLowPriority`.
    private let file: FileItem?
    /// When set, replaces the folder/file type glyph: used by the Favorites list to show a
    /// favorite's custom icon, weight and colour.
    var customIcon: Image?
    var customIconTint: Color?
    var isCustomIconFilled: Bool
    /// When set, the leading thumbnail/icon is the source the preview cover's `.zoom`
    /// transition grows from and shrinks back to.
    var matchedSource: PreviewMatchedSource?
    /// True while this file's content is downloading after a tap: the row shows a trailing
    /// spinner and the full screen preview holds off until it's ready.
    var isOpening: Bool = false
    /// True when this item is downloaded (or covered by a pinned folder) for offline use: the row
    /// shows a small offline badge so the user can tell what's available without a connection.
    var isAvailableOffline: Bool = false
    /// Read live so an already visible row updates immediately when the user changes the
    /// date format in Settings, rather than only on the next fetch.
    @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @AppStorage(AppStorageKeys.includeTimeInDates) private var shouldIncludeTime = false
    @AppStorage(AppStorageKeys.showFilenameExtensions) private var shouldShowFilenameExtensions = true

    /// `thumbnailFile` opts a caller with only a name/kind (a search hit, which carries no size or
    /// modified date) into the same thumbnail rendering a browse row gets, while keeping a custom
    /// `subtitle` (e.g. a search match line) and no date/size line. Server thumbnails still need
    /// the file to report `supportsThumbnail`; the on device document render needs its kind and size.
    init(
        name: String,
        isDirectory: Bool,
        subtitle: String? = nil,
        lineLabel: String? = nil,
        isFavorite: Bool = false,
        kind: String? = nil,
        thumbnailFile: FileItem? = nil,
        serverURL: URL? = nil,
        shouldShowThumbnails: Bool = false,
        customIcon: Image? = nil,
        customIconTint: Color? = nil,
        isCustomIconFilled: Bool = false,
        matchedSource: PreviewMatchedSource? = nil,
        isOpening: Bool = false,
        isAvailableOffline: Bool = false,
        dateModified: Date? = nil,
        size: Int64? = nil,
        shouldWrapText: Bool = false
    ) {
        self.shouldWrapText = shouldWrapText
        self.name = name
        self.isDirectory = isDirectory
        self.isAvailableOffline = isAvailableOffline
        self.dateModified = dateModified
        self.size = isDirectory ? nil : size
        customSubtitle = subtitle
        self.lineLabel = lineLabel
        self.isFavorite = isFavorite
        itemID = thumbnailFile?.id
        self.kind = kind
        supportsThumbnail = thumbnailFile?.supportsThumbnail ?? false
        thumbnailSignature = thumbnailFile?.cacheSignature ?? ""
        self.serverURL = serverURL
        self.shouldShowThumbnails = shouldShowThumbnails
        file = thumbnailFile
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
        shouldShowThumbnails: Bool = false,
        matchedSource: PreviewMatchedSource? = nil,
        isOpening: Bool = false,
        isAvailableOffline: Bool = false,
        folderSize: Int64? = nil
    ) {
        name = item.name
        self.isAvailableOffline = isAvailableOffline
        isDirectory = item.isDirectory
        dateModified = item.hasKnownDate ? item.dateModified : nil
        size = item.isDirectory ? folderSize : item.size
        customSubtitle = nil
        lineLabel = nil
        self.isFavorite = isFavorite
        itemID = item.id
        kind = item.kind
        supportsThumbnail = item.supportsThumbnail
        thumbnailSignature = item.cacheSignature
        self.serverURL = serverURL
        self.shouldShowThumbnails = shouldShowThumbnails
        file = item
        customIcon = nil
        customIconTint = nil
        isCustomIconFilled = false
        self.matchedSource = matchedSource
        self.isOpening = isOpening
    }

    private var dateFormat: DateDisplayFormat {
        DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
    }

    private var subtitle: String? {
        if let customSubtitle {
            return customSubtitle
        }
        guard let dateModified else { return nil }
        let dateText = dateFormat.string(from: dateModified, includeTime: shouldIncludeTime)
        guard let size else { return dateText }
        return "\(FileSizeFormat.string(size)) • \(dateText)"
    }

    private var isHidden: Bool {
        isHiddenFileName(name)
    }

    private var displayName: String {
        displayFileName(name, isDirectory: isDirectory, showExtension: shouldShowFilenameExtensions)
    }

    private var isEligibleForThumbnail: Bool {
        !isDirectory && (supportsThumbnail || shouldReadOwnContent) && shouldShowThumbnails && serverURL != nil &&
            itemID !=
            nil
    }

    /// Audio (cover art) and text (its first lines) have no server thumbnail: the app draws their own.
    private var shouldReadOwnContent: Bool {
        kind.map(ThumbnailImage.shouldReadOwnContent) ?? false
    }

    private var isEligibleForDocumentThumbnail: Bool {
        shouldShowThumbnails && serverURL != nil && file.map(DocumentThumbnailStore.isEligible) == true
    }

    var body: some View {
        HStack(spacing: .space12) {
            leadingIcon
                .opacity(isHidden ? Constants.halfOpacity : Constants.fullOpacity)
                .previewMatchedSource(matchedSource)

            VStack(alignment: .leading, spacing: .space2) {
                Text(displayName)
                    .type(.body2(.semibold), style: isHidden ? .tertiary : .primaryOnSurface)
                    .lineLimit(shouldWrapText ? nil : 1)
                if let subtitle {
                    Text(subtitle)
                        .type(.body3(.regular), style: isHidden ? .tertiary : .secondary)
                        .lineLimit(shouldWrapText ? nil : 1)
                }
                if let lineLabel {
                    Text(lineLabel)
                        .type(.body3(.semibold), style: isHidden ? .tertiary : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isOpening {
                DSSpinner()
                    .controlSize(.small)
            }

            if isAvailableOffline {
                IconKit.availableOffline
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: .iconSmall, height: .iconSmall)
                    .symbolEffect(.bounce, value: isAvailableOffline)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(L10n.Offline.badgeAvailable)
            }

            if isFavorite {
                IconKit.starFill
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: .iconSmall, height: .iconSmall)
                    .symbolEffect(.bounce, value: isFavorite)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(L10n.Favorites.accessibilityBadge)
            }

            if isDirectory {
                IconKit.chevronRight
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.chevronSize, height: Constants.chevronSize)
            }
        }
        .padding(.vertical, .space4)
        .contentShape(Rectangle())
        .animation(
            DSMotion.pop,
            value: isFavorite
        )
        .animation(
            DSMotion.pop,
            value: isAvailableOffline
        )
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let customIcon {
            FavoriteGlyph(icon: customIcon, tint: customIconTint, isFilled: isCustomIconFilled)
        } else if isEligibleForThumbnail, let serverURL, let itemID {
            ThumbnailImage(
                serverURL: serverURL, path: itemID, signature: thumbnailSignature, fallbackIcon: IconKit.document,
                fallbackKind: kind,
                iconTint: Color.secondaryDS, fileSize: file?.size, modified: file?.dateModified
            )
            .frame(width: Constants.iconFrame, height: Constants.iconFrame)
        } else if isEligibleForDocumentThumbnail, let serverURL, let file {
            DocumentThumbnailImage(serverURL: serverURL, item: file) {
                FileTypeIcon(kind: file.kind)
            }
            .frame(width: Constants.iconFrame, height: Constants.iconFrame)
        } else if isDirectory {
            IconKit.folderFill
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
                .frame(width: Constants.iconFrame, height: Constants.iconFrame)
        } else {
            FileTypeIcon(kind: kind ?? "")
                .frame(width: Constants.iconFrame, height: Constants.iconFrame)
        }
    }
}

/// Dotfile convention (`.something`): the server's own default `hiddenFiles` pattern
/// (`backend/src/config/index.js`, confirmed via `hidden-files-config.test.js`) before
/// an admin adds extra `HIDDEN_FILE_PATTERNS`, which this client has no way to know about.
func isHiddenFileName(_ name: String) -> Bool {
    name.hasPrefix(".")
}

/// Strips the extension from a file's display name when the "Show Filename Extensions"
/// setting is off. Directories never have a meaningful extension to strip, and
/// `NSString.deletingPathExtension` already leaves a bare dotfile like `.hidden` untouched
/// (Foundation doesn't treat the leading dot itself as an extension separator).
func displayFileName(_ name: String, isDirectory: Bool, showExtension: Bool) -> String {
    guard !isDirectory, !showExtension else { return name }
    return (name as NSString).deletingPathExtension
}

#Preview {
    VStack(spacing: .space16) {
        FileRowView(
            name: "Folder",
            isDirectory: true,
            subtitle: nil
        )
        FileRowView(
            name: "Folder",
            isDirectory: true,
            subtitle: "Aug 20, 2026"
        )
        FileRowView(
            name: "Favorite Folder",
            isDirectory: true,
            subtitle: "Aug 20, 2026",
            isFavorite: true
        )
        FileRowView(
            name: ".hidden",
            isDirectory: true,
            subtitle: nil
        )
        FileRowView(
            name: "File",
            isDirectory: false,
            subtitle: nil
        )
        FileRowView(
            name: ".hidden",
            isDirectory: false,
            subtitle: nil
        )
        FileRowView(
            name: "File",
            isDirectory: false,
            subtitle: "18kb"
        )
        FileRowView(
            name: "Favorite File",
            isDirectory: false,
            subtitle: "18kb",
            isFavorite: true
        )
        FileRowView(
            name: ".hidden",
            isDirectory: false,
            subtitle: "18kb"
        )
        FileRowView(
            name: "ContentView.swift",
            isDirectory: false,
            subtitle: "let count = 0",
            lineLabel: "Line 58"
        )
    }
    .padding(.space16)
}

#Preview("Thumbnails on") {
    // `.previewValue`'s `thumbnailURL` always resolves to `nil`, so this renders the same
    // fallback icon as any other file: it documents/exercises the code path rather than
    // showing an actual image.
    FileRowView(
        item: FileItem(
            name: "vacation.jpg",
            path: "",
            dateModified: Date(),
            size: 2_400_000,
            kind: "jpg",
            supportsThumbnail: true
        ),
        serverURL: URL(string: "https://nextexplorer.example.com"),
        shouldShowThumbnails: true
    )
    .padding(.space16)
}

#Preview("Thumbnails off (with fallback)") {
    FileRowView(
        item: FileItem(
            name: "vacation.jpg",
            path: "",
            dateModified: Date(),
            size: 2_400_000,
            kind: "jpg",
            supportsThumbnail: true
        ),
        serverURL: URL(string: "https://nextexplorer.example.com"),
        shouldShowThumbnails: false
    )
    .padding(.space16)
}
