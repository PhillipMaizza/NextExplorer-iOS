#if os(macOS)
    import DesignSystem
    import SwiftUI

    struct MacItemIcon: View {
        let kind: String
        let isDirectory: Bool

        init(kind: String, isDirectory: Bool) {
            self.kind = kind
            self.isDirectory = isDirectory
        }

        init(name: String, isDirectory: Bool) {
            self.init(kind: (name as NSString).pathExtension.lowercased(), isDirectory: isDirectory)
        }

        var body: some View {
            Group {
                if isDirectory {
                    MacTableFolderIcon(image: IconKit.folderFill, tint: Color.accent)
                } else {
                    FileTypeIcon(kind: kind)
                        .frame(width: MacBrowseTableMetrics.iconSize, height: MacBrowseTableMetrics.iconSize)
                }
            }
            .accessibilityHidden(true)
        }
    }

    struct MacItemTile: View {
        let kind: String
        let isDirectory: Bool
        let size: CGFloat
        var folderGlyph = IconKit.folderFill
        @Environment(\.backgroundProminence) private var prominence

        var body: some View {
            Group {
                if isDirectory {
                    MacFolderTile(size: size, glyph: folderGlyph)
                } else {
                    FileTypeIcon(kind: kind)
                        .background(
                            prominence == .increased ? Color.macCard : .clear,
                            in: RoundedRectangle(
                                cornerRadius: size * FileTypeIcon.cornerFraction,
                                style: .continuous
                            )
                        )
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    extension MacItemTile {
        init(name: String, isDirectory: Bool, size: CGFloat = MacBrowseTableMetrics.tileSize) {
            self.init(kind: (name as NSString).pathExtension.lowercased(), isDirectory: isDirectory, size: size)
        }
    }

    #Preview("Tiles") {
        HStack(spacing: .space16) {
            MacItemTile(kind: "directory", isDirectory: true, size: .size40)
            MacItemTile(kind: "md", isDirectory: false, size: .size40)
            MacItemTile(kind: "directory", isDirectory: true, size: .size64)
        }
        .padding()
        .background(Color.macCard)
    }

    #Preview("Folder and file") {
        HStack(spacing: .space16) {
            MacItemIcon(name: "Media", isDirectory: true)
            MacItemIcon(name: "Welcome.pdf", isDirectory: false)
            MacItemIcon(name: "vacation.jpg", isDirectory: false)
        }
        .padding()
        .background(Color.macCard)
    }
#endif
