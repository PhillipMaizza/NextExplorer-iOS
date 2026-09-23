#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The table mode stand in while a folder's first page loads: the same columns and widths as
    /// `MacBrowseTableView`, with redacted, shimmering rows, so the loaded table fades in without
    /// a layout jump. Non interactive.
    struct MacBrowseTableSkeleton: View {
        var body: some View {
            Table(BrowseSkeletonView.placeholderItems) {
                TableColumn(L10n.Sort.name) { item in
                    placeholder(
                        HStack(spacing: .space8) {
                            FileTypeIcon(kind: item.kind)
                                .frame(width: MacBrowseTableMetrics.iconSize, height: MacBrowseTableMetrics.iconSize)
                            Text(item.name)
                        }
                    )
                }
                .width(min: MacBrowseTableMetrics.nameColumnMinWidth)
                TableColumn(L10n.Sort.dateModified) { item in
                    placeholder(Text(item.dateModified, format: .dateTime))
                }
                .width(MacBrowseTableMetrics.dateColumnWidth)
                TableColumn(L10n.Sort.size) { item in
                    placeholder(Text(item.size, format: .byteCount(style: .file)))
                }
                .width(MacBrowseTableMetrics.sizeColumnWidth)
                TableColumn(L10n.Sort.kind) { _ in
                    placeholder(Text(verbatim: "MMMM"))
                }
                .width(MacBrowseTableMetrics.kindColumnWidth)
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .backgroundGradient()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        /// Redacted and shimmering per cell, as `BrowseSkeletonView` does per row, so the shine
        /// tracks the bars instead of washing over the whole table.
        private func placeholder(_ content: some View) -> some View {
            content
                .foregroundStyle(Color.secondaryDS)
                .redacted(reason: .placeholder)
                .shimmering()
        }
    }

    #Preview("Table skeleton") {
        MacBrowseTableSkeleton()
            .frame(width: 900, height: 500)
    }
#endif
