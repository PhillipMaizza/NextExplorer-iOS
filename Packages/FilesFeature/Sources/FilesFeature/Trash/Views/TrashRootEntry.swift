import DesignSystem
import Localization
import SwiftUI

/// The Trash row at the end of the Browse root list.
struct TrashRootRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FileRowView(
                name: L10n.Trash.title,
                isDirectory: true,
                subtitle: L10n.Trash.rowSubtitle,
                customIcon: IconKit.delete,
                customIconTint: .secondaryDS
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.Trash.rowSubtitle)
    }
}

/// The grid mode counterpart of `TrashRootRow`.
struct TrashRootGridCell: View {
    let iconSize: CGFloat
    let cellPadding: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GridCellView(
                name: L10n.Trash.title,
                isDirectory: true,
                iconSize: iconSize,
                customIcon: IconKit.delete,
                customIconTint: .secondaryDS
            )
            .dsGridTile(padding: cellPadding)
        }
        .buttonStyle(DSPressableButtonStyle())
        .accessibilityHint(L10n.Trash.rowSubtitle)
    }
}

#Preview("Row") {
    List {
        TrashRootRow {}
    }
}

#Preview("Row, dark, large type") {
    List {
        TrashRootRow {}
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}

#Preview("Grid cell") {
    TrashRootGridCell(iconSize: .iconLarge, cellPadding: .space8) {}
        .frame(width: 120)
        .padding()
}
