#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacBrowseNameCell: View {
        let item: FileItem
        let title: String
        var glyph = IconKit.folderFill
        var serverURL: URL?
        var isRenaming = false
        var isCut = false
        var isOffline = false
        var isFavorite = false
        var onRenameCommit: (String) -> Void = { _ in }
        var onRenameCancel: () -> Void = {}

        var body: some View {
            HStack(spacing: .space8) {
                tile
                if isRenaming {
                    MacInlineRenameField(
                        originalName: item.name,
                        onCommit: onRenameCommit,
                        onCancel: onRenameCancel
                    )
                } else {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityValue(isCut ? L10n.Browse.actionCut : "")
                }
                if isOffline {
                    MacTableFolderIcon(
                        image: IconKit.availableOffline,
                        tint: Color.accent,
                        size: MacBrowseTableMetrics.badgeSize
                    )
                    .accessibilityLabel(L10n.Offline.badgeAvailable)
                }
                if isFavorite {
                    MacTableFolderIcon(
                        image: IconKit.starFill,
                        tint: Color.accent,
                        size: MacBrowseTableMetrics.badgeSize
                    )
                    .accessibilityLabel(L10n.Favorites.accessibilityBadge)
                }
            }
        }
    }

    extension MacBrowseNameCell {
        @ViewBuilder
        private var tile: some View {
            if let serverURL, !item.isDirectory, item.isImage || item.isVideo || item.isAudio {
                ThumbnailImage(
                    serverURL: serverURL,
                    path: item.id,
                    signature: item.cacheSignature,
                    fallbackIcon: IconKit.document,
                    fallbackKind: item.kind,
                    iconTint: Color.secondaryDS,
                    maxPixelDimension: MacBrowseTableMetrics.thumbnailMaxPixels,
                    fileSize: item.size,
                    modified: item.dateModified,
                    fill: .crop
                )
                .frame(width: MacBrowseTableMetrics.tileSize, height: MacBrowseTableMetrics.tileSize)
                .clipShape(RoundedRectangle(cornerRadius: MacBrowseTableMetrics.tileRadius, style: .continuous))
                .overlay {
                    if item.isVideo {
                        IconKit.play
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: MacBrowseTableMetrics.playGlyphSize,
                                height: MacBrowseTableMetrics.playGlyphSize
                            )
                            .foregroundStyle(.white)
                            .shadow(radius: MacBrowseTableMetrics.playGlyphShadow)
                    }
                }
            } else if let serverURL, DocumentThumbnailStore.isEligible(item) {
                DocumentThumbnailImage(serverURL: serverURL, item: item) {
                    MacItemTile(kind: item.kind, isDirectory: false, size: MacBrowseTableMetrics.tileSize)
                }
                .frame(width: MacBrowseTableMetrics.tileSize, height: MacBrowseTableMetrics.tileSize)
            } else {
                MacItemTile(
                    kind: item.kind,
                    isDirectory: item.isDirectory,
                    size: MacBrowseTableMetrics.tileSize,
                    folderGlyph: glyph
                )
            }
        }
    }

    private enum PreviewFixture {
        static let folder = FileItem(name: "Projects", path: "", dateModified: .distantPast, size: 0, kind: "directory")
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        static let photo = FileItem(
            name: "beach.jpg",
            path: "",
            dateModified: .distantPast,
            size: 2_400_000,
            kind: "jpg"
        )
        static let file = FileItem(name: "report.pdf", path: "", dateModified: .distantPast, size: 182_000, kind: "pdf")
    }

    #Preview("Name cells") {
        VStack(alignment: .leading, spacing: .space12) {
            MacBrowseNameCell(item: PreviewFixture.folder, title: PreviewFixture.folder.name, isFavorite: true)
            MacBrowseNameCell(item: PreviewFixture.file, title: PreviewFixture.file.name, isOffline: true)
            MacBrowseNameCell(item: PreviewFixture.folder, title: L10n.Browse.myFiles, glyph: IconKit.person)
            MacBrowseNameCell(item: PreviewFixture.file, title: PreviewFixture.file.name, isRenaming: true)
            MacBrowseNameCell(
                item: PreviewFixture.photo,
                title: PreviewFixture.photo.name,
                serverURL: PreviewFixture.serverURL
            )
        }
        .padding()
        .previewCanvasWidth(.dialog)
        .background(Color.macCard)
    }
#endif
