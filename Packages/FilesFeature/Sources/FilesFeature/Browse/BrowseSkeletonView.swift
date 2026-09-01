import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let gridSpacing: CGFloat = .space16
    /// Inset between a grid tile's content and its `backgroundSecondary` card edge, matching
    /// `BrowseContentView`.
    static let gridCellPadding: CGFloat = .space12
    /// Name width + byte size per placeholder row, deliberately uneven so the redacted title
    /// and subtitle bars don't line up as two flat columns.
    static let placeholderShapes: [(nameLength: Int, size: Int64)] = [
        (6, 2_100), (13, 480_000), (4, 12), (9, 6_400), (16, 3_900_000), (7, 55_000),
        (11, 780), (5, 240_000), (14, 9_100), (8, 1_600_000), (10, 33), (6, 128_000),
    ]
    static let placeholderNameChar = "M"
    static let skeleton = "skeleton/"
}

/// Redacted `FileRowView` / `GridCellView` stand-ins shown while a folder's first page loads
/// (`BrowseContentView` swaps it in for the list), so the shape of what's coming is already on
/// screen instead of a bare spinner. Reuses the real `List`/`ScrollView` containers so
/// margins, row height and the `backgroundSecondary` surface line up exactly, with scrolling
/// disabled. Non-interactive; the shine is suppressed under Reduce Motion by `.shimmering()`.
struct BrowseSkeletonView: View {
    let isGridView: Bool
    let gridColumns: [GridItem]
    let iconSize: CGFloat

    /// All plain files — a redacted directory row keeps its accent tinted folder glyph and
    /// trailing chevron, which survive `.redacted` as gold blocks. Uniform file rows read as
    /// a clean skeleton. Built once — this view can stay mounted at zero opacity behind a
    /// crossfade, so a per-render rebuild would be wasted work.
    private static let placeholderItems: [FileItem] = Constants.placeholderShapes.enumerated().map { index, shape in
        FileItem(
            name: String(repeating: Constants.placeholderNameChar, count: shape.nameLength),
            path: "\(Constants.skeleton)\(index)",
            dateModified: Date(timeIntervalSince1970: 1_600_000_000 - Double(index) * 86_400 * 37),
            size: shape.size,
            kind: ""
        )
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .backgroundGradient()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// `.redacted` + `.shimmering()` is applied per row/cell, not to the whole container:
    /// masking the shimmer's sweep with a `List`/`ScrollView` collapses to an opaque
    /// rectangle, so the shine reads as a dim vertical bar over everything (gaps included)
    /// and the accent gradient bleeds through the `.plusLighter` blend. A leaf view gives a
    /// real alpha mask, so the shine tracks the redacted bars.
    private func placeholderRow(_ content: some View) -> some View {
        content
            .redacted(reason: .placeholder)
            .shimmering()
    }

    @ViewBuilder
    private var content: some View {
        if isGridView {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: Constants.gridSpacing) {
                    ForEach(Self.placeholderItems) { item in
                        placeholderRow(
                            GridCellView(item: item, iconSize: iconSize)
                                .dsCard(padding: Constants.gridCellPadding)
                        )
                    }
                }
                .padding(Constants.gridSpacing)
            }
            .scrollDisabled(true)
        } else {
            List {
                Section {
                    ForEach(Self.placeholderItems) { item in
                        placeholderRow(FileRowView(item: item))
                            .listRowBackground(Color.backgroundSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
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
