import DesignSystem
import Localization
import SwiftUI

/// The account's private folder when the server has personal folders on. The backend reaches it
/// through the logical `personal` path space (`parsePathSpace` in `backend/src/utils/pathUtils.js`)
/// and never lists it among the volumes, so the root screen offers it as its own entry.
enum PersonalSpace {
    static let rootPath = "personal"

    /// A breadcrumb or title for a path segment: the leading `personal` reads as "My Files".
    static func displayName(forSegment segment: String, isFirstSegment: Bool) -> String {
        isFirstSegment && segment == rootPath ? L10n.Browse.myFiles : segment
    }
}

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
