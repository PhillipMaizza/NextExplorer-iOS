import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let rowCount = 12
    static let gridSpacing: CGFloat = .space16
    /// Inset between a grid tile's content and its `backgroundSecondary` card edge, matching
    /// `BrowseContentView`.
    static let gridCellPadding: CGFloat = .space12
    /// Varied name widths so the redacted title bars don't render as one flat column.
    static let nameLengths = [7, 12, 5, 9, 15, 6, 11, 4, 13, 8, 10, 6]
    static let placeholderNameChar = "M"
    static let skeleton = "skeleton/"
}

/// Redacted `FileRowView` / `GridCellView` stand-ins shown while a folder's first page
/// loads, so the shape of what's coming is already on screen instead of a bare spinner.
/// Reuses the real `List`/`ScrollView` containers so margins, row height and the
/// `backgroundSecondary` surface line up exactly with the content that replaces it, but with
/// scrolling disabled so it never drives the nav bar. Non-interactive. The shine is
/// suppressed under Reduce Motion by `.shimmering()`.
struct BrowseSkeletonView: View {
    let isGridView: Bool
    let gridColumns: [GridItem]
    let iconSize: CGFloat

    /// All plain files — a redacted directory row keeps its accent tinted folder glyph and
    /// trailing chevron, which survive `.redacted` as gold blocks. Uniform file rows read as
    /// a clean skeleton.
    private var placeholderItems: [FileItem] {
        Constants.nameLengths.prefix(Constants.rowCount).enumerated().map { index, length in
            FileItem(
                name: String(repeating: Constants.placeholderNameChar, count: length),
                path: "\(Constants.skeleton)\(index)",
                dateModified: .distantPast,
                size: 1_024,
                kind: ""
            )
        }
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
                    ForEach(placeholderItems) { item in
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
                    ForEach(placeholderItems) { item in
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
