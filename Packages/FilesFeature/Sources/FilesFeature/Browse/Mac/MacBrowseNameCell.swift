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
                MacFileTile(item: item, serverURL: serverURL, glyph: glyph)
                if isRenaming {
                    MacInlineRenameField(
                        originalName: item.name,
                        isDirectory: item.isDirectory,
                        onCommit: onRenameCommit,
                        onCancel: onRenameCancel
                    )
                } else {
                    MacFileNameText(name: title, isDirectory: item.isDirectory)
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
