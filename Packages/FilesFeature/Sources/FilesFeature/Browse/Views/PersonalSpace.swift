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
struct PersonalSpaceRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FileRowView(
                name: L10n.Browse.myFiles,
                isDirectory: true,
                subtitle: L10n.Browse.myFilesSubtitle,
                customIcon: IconKit.person,
                customIconTint: .accent
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.Browse.myFilesSubtitle)
    }
}

struct PersonalSpaceGridCell: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GridCellView(
                name: L10n.Browse.myFiles,
                isDirectory: true,
                customIcon: IconKit.person,
                customIconTint: .accent
            )
            .dsGridTile()
        }
        .buttonStyle(DSPressableButtonStyle())
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
    PersonalSpaceGridCell(onTap: {})
        .frame(width: 180)
        .padding()
}
