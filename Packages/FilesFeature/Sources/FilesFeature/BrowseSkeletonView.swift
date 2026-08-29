import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let rowCount = 12
    static let gridSpacing: CGFloat = .space16
    static let rowHorizontalInset: CGFloat = .space16
    static let separatorLeadingInset: CGFloat = .space48 + .space16
    /// Varied name widths so the redacted title bars don't render as one flat column.
    static let nameLengths = [7, 12, 5, 9, 15, 6, 11, 4, 13, 8, 10, 6]
    static let placeholderNameChar = "M"
    static let skeleton = "skeleton/"
    static let directory = "directory"
    static let directoryEvery = 3
}

/// Redacted `FileRowView` / `GridCellView` stand-ins shown while a folder's first page
/// loads, so the shape of what's coming is already on screen instead of a bare spinner.
/// Non-scrolling and non-interactive: it stands in for the real `List`/grid only until the
/// first response lands, so it must not register a second scroll view with the nav bar. The
/// shine is suppressed under Reduce Motion by `.shimmering()`.
struct BrowseSkeletonView: View {
    let isGridView: Bool
    let gridColumns: [GridItem]
    let iconSize: CGFloat

    private var placeholderItems: [FileItem] {
        Constants.nameLengths.prefix(Constants.rowCount).enumerated().map { index, length in
            FileItem(
                name: String(repeating: Constants.placeholderNameChar, count: length),
                path: "\(Constants.skeleton)\(index)",
                dateModified: .distantPast,
                size: 1_024,
                kind: index.isMultiple(of: Constants.directoryEvery) ? Constants.directory : ""
            )
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .redacted(reason: .placeholder)
            .shimmering()
            // Gradient last so it sits at full opacity behind the shimmer's dimmed content,
            // rather than being dimmed to ~45% along with everything else.
            .backgroundGradient()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if isGridView {
            LazyVGrid(columns: gridColumns, spacing: Constants.gridSpacing) {
                ForEach(placeholderItems) { item in
                    GridCellView(item: item, iconSize: iconSize)
                }
            }
            .padding(Constants.gridSpacing)
        } else {
            VStack(spacing: 0) {
                ForEach(placeholderItems) { item in
                    FileRowView(item: item)
                        .padding(.horizontal, Constants.rowHorizontalInset)
                    if item.id != placeholderItems.last?.id {
                        Divider().padding(.leading, Constants.separatorLeadingInset)
                    }
                }
            }
        }
    }
}

#Preview("List") {
    BrowseSkeletonView(isGridView: false, gridColumns: [], iconSize: .iconLarge)
}

#Preview("Grid") {
    BrowseSkeletonView(
        isGridView: true,
        gridColumns: [GridItem(.adaptive(minimum: .size96), spacing: .space16)],
        iconSize: .iconLarge
    )
}
