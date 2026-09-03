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
    static let favoriteSpringResponse: Double = 0.3
    static let favoriteSpringDamping: Double = 0.7
}

struct FileRowView: View {
    let name: String
    let isDirectory: Bool
    let dateModified: Date?
    let size: Int64?
    let customSubtitle: String?
    /// A small semibold line rendered under the subtitle, e.g. "Line 58" for a search content
    /// match. `nil` hides it.
    let lineLabel: String?
    let isFavorite: Bool
    let itemID: String?
    let kind: String?
    let supportsThumbnail: Bool
    let thumbnailSignature: String
    let serverURL: URL?
    let showThumbnails: Bool
    /// The full item, when built from one — needed for the on device PDF first page render,
    /// which fetches the file through `filesClient.previewFileLowPriority`.
    private let file: FileItem?
    /// When set, replaces the folder/file-type glyph — used by the Favorites list to show a
    /// favorite's custom icon, weight and colour.
    var customIcon: Image?
    var customIconTint: Color?
    var customIconFilled: Bool
    /// When set, the leading thumbnail/icon is the source the preview cover's `.zoom`
    /// transition grows from and shrinks back to.
    var matchedSource: PreviewMatchedSource?
    /// True while this file's content is downloading after a tap — the row shows a trailing
    /// spinner and the full-screen preview holds off until it's ready.
    var isOpening: Bool = false
    /// Read live so an already-visible row updates immediately when the user changes the
    /// date format in Settings, rather than only on the next fetch.
    @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @AppStorage(AppStorageKeys.includeTimeInDates) private var includeTime = false
    @AppStorage(AppStorageKeys.showFilenameExtensions) private var showFilenameExtensions = true

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// `thumbnailFile` opts a caller with only a name/kind (a search hit, which carries no size or
    /// modified date) into the same thumbnail rendering a browse row gets, while keeping a custom
    /// `subtitle` (e.g. a search match line) and no date/size line. Server thumbnails still need
    /// the file to report `supportsThumbnail`; the on device PDF render only needs its kind.
    init(
        name: String,
        isDirectory: Bool,
        subtitle: String? = nil,
        lineLabel: String? = nil,
        isFavorite: Bool = false,
        kind: String? = nil,
        thumbnailFile: FileItem? = nil,
        serverURL: URL? = nil,
        showThumbnails: Bool = false,
        customIcon: Image? = nil,
        customIconTint: Color? = nil,
        customIconFilled: Bool = false,
        matchedSource: PreviewMatchedSource? = nil,
        isOpening: Bool = false
    ) {
        self.name = name
        self.isDirectory = isDirectory
        self.dateModified = nil
        self.size = nil
        self.customSubtitle = subtitle
        self.lineLabel = lineLabel
        self.isFavorite = isFavorite
        self.itemID = thumbnailFile?.id
        self.kind = kind
        self.supportsThumbnail = thumbnailFile?.supportsThumbnail ?? false
        self.thumbnailSignature = thumbnailFile?.cacheSignature ?? ""
        self.serverURL = serverURL
        self.showThumbnails = showThumbnails
        self.file = thumbnailFile
        self.customIcon = customIcon
        self.customIconTint = customIconTint
        self.customIconFilled = customIconFilled
        self.matchedSource = matchedSource
        self.isOpening = isOpening
    }

    init(item: FileItem, isFavorite: Bool = false, serverURL: URL? = nil, showThumbnails: Bool = false, matchedSource: PreviewMatchedSource? = nil, isOpening: Bool = false) {
        self.name = item.name
        self.isDirectory = item.isDirectory
        self.dateModified = item.dateModified
        self.size = item.isDirectory ? nil : item.size
        self.customSubtitle = nil
        self.lineLabel = nil
        self.isFavorite = isFavorite
        self.itemID = item.id
        self.kind = item.kind
        self.supportsThumbnail = item.supportsThumbnail
        self.thumbnailSignature = item.cacheSignature
        self.serverURL = serverURL
        self.showThumbnails = showThumbnails
        self.file = item
        self.customIcon = nil
        self.customIconTint = nil
        self.customIconFilled = false
        self.matchedSource = matchedSource
        self.isOpening = isOpening
    }

    private var dateFormat: DateDisplayFormat { DateDisplayFormat(rawValue: dateFormatRaw) ?? .system }

    private var subtitle: String? {
        if let customSubtitle { return customSubtitle }
        guard let dateModified else { return nil }
        let dateText = dateFormat.string(from: dateModified, includeTime: includeTime)
        guard let size else { return dateText }
        return "\(Self.byteFormatter.string(fromByteCount: size)) • \(dateText)"
    }

    private var isHidden: Bool { isHiddenFileName(name) }

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
        HStack(spacing: .space12) {
            leadingIcon
                .opacity(isHidden ? Constants.halfOpacity : Constants.fullOpacity)
                .previewMatchedSource(matchedSource)

            VStack(alignment: .leading, spacing: .space2) {
                Text(displayName)
                    .type(.body2(.semibold), style: isHidden ? .tertiary : .primary(for: .label))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .type(.body3(.regular), style: isHidden ? .tertiary : .secondary)
                        .lineLimit(1)
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
        .animation(.spring(response: Constants.favoriteSpringResponse, dampingFraction: Constants.favoriteSpringDamping), value: isFavorite)
        // Only favoriting buzzes — un-favoriting isn't a "win" worth celebrating the same way.
        .hapticFeedback(.success, trigger: isFavorite) { _, isFavorite in isFavorite }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let customIcon {
            customIcon
                .resizable()
                .scaledToFit()
                .symbolVariant(customIconFilled ? .fill : .none)
                .foregroundStyle(customIconTint ?? Color.accent)
                .frame(width: Constants.iconFrame, height: Constants.iconFrame)
        } else if isEligibleForThumbnail, let serverURL, let itemID {
            ThumbnailImage(serverURL: serverURL, path: itemID, signature: thumbnailSignature, fallbackIcon: IconKit.document, iconTint: Color.secondaryDS)
                .frame(width: Constants.iconFrame, height: Constants.iconFrame)
        } else if isEligibleForPDFThumbnail, let serverURL, let file {
            PDFThumbnailImage(serverURL: serverURL, item: file)
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
        FileRowView(name: "Folder",
                    isDirectory: true,
                    subtitle: nil)
        FileRowView(name: "Folder",
                    isDirectory: true,
                    subtitle: "Aug 20, 2026")
        FileRowView(name: "Favorite Folder",
                    isDirectory: true,
                    subtitle: "Aug 20, 2026",
                    isFavorite: true)
        FileRowView(name: ".hidden",
                    isDirectory: true,
                    subtitle: nil)
        FileRowView(name: "File",
                    isDirectory: false,
                    subtitle: nil)
        FileRowView(name: ".hidden",
                    isDirectory: false,
                    subtitle: nil)
        FileRowView(name: "File",
                    isDirectory: false,
                    subtitle: "18kb")
        FileRowView(name: "Favorite File",
                    isDirectory: false,
                    subtitle: "18kb",
                    isFavorite: true)
        FileRowView(name: ".hidden",
                    isDirectory: false,
                    subtitle: "18kb")
        FileRowView(name: "ContentView.swift",
                    isDirectory: false,
                    subtitle: "let count = 0",
                    lineLabel: "Line 58")

    }
    .padding(.space16)
}

#Preview("Thumbnails on") {
    // `.previewValue`'s `thumbnailURL` always resolves to `nil`, so this renders the same
    // fallback icon as any other file — it documents/exercises the code path rather than
    // showing an actual image.
    FileRowView(
        item: FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg", supportsThumbnail: true),
        serverURL: URL(string: "https://nextexplorer.example.com"),
        showThumbnails: true
    )
    .padding(.space16)
}

#Preview("Thumbnails off (falls back to the plain icon even though the file supports one)") {
    FileRowView(
        item: FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg", supportsThumbnail: true),
        serverURL: URL(string: "https://nextexplorer.example.com"),
        showThumbnails: false
    )
    .padding(.space16)
}
