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
