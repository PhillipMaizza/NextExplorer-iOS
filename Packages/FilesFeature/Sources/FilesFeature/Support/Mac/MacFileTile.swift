#if os(macOS)
    import CoreModels
    import DesignSystem
    import SwiftUI

    struct MacFileTile: View {
        let item: FileItem
        var serverURL: URL?
        var glyph = IconKit.folderFill
        var size: CGFloat = MacBrowseTableMetrics.tileSize
        var shouldShowPlayBadge = true

        private var radius: CGFloat {
            MacBrowseTableMetrics.tileRadius * size / MacBrowseTableMetrics.tileSize
        }

        var body: some View {
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
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    if item.isVideo, shouldShowPlayBadge {
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
                    MacItemTile(kind: item.kind, isDirectory: false, size: size)
                }
                .frame(width: size, height: size)
            } else {
                MacItemTile(
                    kind: item.kind,
                    isDirectory: item.isDirectory,
                    size: size,
                    folderGlyph: glyph
                )
            }
        }
    }

    #Preview("File tiles") {
        HStack(spacing: .space16) {
            MacFileTile(item: FileItem(
                name: "Projects",
                path: "",
                dateModified: .distantPast,
                size: 0,
                kind: "directory"
            ))
            MacFileTile(item: FileItem(name: "notes.pdf", path: "", dateModified: .distantPast, size: 0, kind: "pdf"))
        }
        .padding(.space16)
    }
#endif
