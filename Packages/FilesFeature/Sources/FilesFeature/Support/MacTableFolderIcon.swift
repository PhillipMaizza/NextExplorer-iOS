#if os(macOS)
    import DesignSystem
    import SwiftUI

    /// A tinted symbol sized for a table row's leading icon.
    struct MacTableFolderIcon: View {
        let image: Image
        let tint: Color
        var isFilled = true
        var size: CGFloat = MacBrowseTableMetrics.iconSize

        var body: some View {
            image
                .resizable()
                .scaledToFit()
                .symbolVariant(isFilled ? .fill : .none)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

    #Preview {
        HStack(spacing: .space16) {
            MacTableFolderIcon(image: IconKit.folderFill, tint: Color.accent)
            MacTableFolderIcon(image: IconKit.person, tint: Color.accent)
            MacTableFolderIcon(image: IconKit.download, tint: Color.accent, size: MacBrowseTableMetrics.badgeSize)
        }
        .padding(.space16)
    }
#endif
