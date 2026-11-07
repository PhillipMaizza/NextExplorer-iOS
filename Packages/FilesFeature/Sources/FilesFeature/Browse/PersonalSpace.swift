import DesignSystem
import Localization
import SwiftUI

/// "Personal" and "Locations" headings on the Browse root, shown only when the personal space
/// sits above the volumes so the two kinds of folder read as separate groups.
struct BrowseRootSectionHeader: View {
    let title: String

    var body: some View {
        DSFieldLabel(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The "My Files" row pinned above the volumes on the Browse root list.
///
/// A bare `List` row button may fire without ever reporting `isPressed` (the volume rows get it
/// through their context menu interaction), so the press haptic is tied to the tap instead.
struct PersonalSpaceRow: View {
    let onTap: () -> Void
    @State private var tapCount = 0

    var body: some View {
        Button {
            tapCount += 1
            onTap()
        } label: {
            FileRowView(
                name: L10n.Browse.myFiles,
                isDirectory: true,
                subtitle: L10n.Browse.myFilesSubtitle,
                customIcon: IconKit.person,
                customIconTint: .accent
            )
        }
        .buttonStyle(.plain)
        .hapticFeedback(.impact(weight: .light), trigger: tapCount)
        .accessibilityHint(L10n.Browse.myFilesSubtitle)
    }
}

/// The grid mode counterpart of `PersonalSpaceRow`.
struct PersonalSpaceGridCell: View {
    let iconSize: CGFloat
    let cellPadding: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GridCellView(
                name: L10n.Browse.myFiles,
                isDirectory: true,
                iconSize: iconSize,
                customIcon: IconKit.person,
                customIconTint: .accent
            )
            .dsCard(padding: cellPadding)
        }
        .buttonStyle(DSHapticButtonStyle())
        .accessibilityHint(L10n.Browse.myFilesSubtitle)
    }
}

#Preview("Row") {
    List {
        Section {
            PersonalSpaceRow(onTap: {})
        } header: {
            BrowseRootSectionHeader(title: "Personal")
        }
    }
}

#Preview("Grid cell") {
    PersonalSpaceGridCell(iconSize: .size56, cellPadding: .space8, onTap: {})
        .frame(width: 120)
        .padding()
}
