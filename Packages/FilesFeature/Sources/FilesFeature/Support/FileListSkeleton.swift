import DesignSystem
import SwiftUI

/// One redacted placeholder: a name and, for a file, an optional second line.
struct SkeletonEntry: Hashable {
    let name: String
    var isDirectory = false
    var subtitle: String?

    /// Placeholder text `count` characters wide.
    static func text(_ count: Int) -> String {
        String(repeating: "M", count: count)
    }
}

/// Redacted `FileRowView` stand ins that sit in the same `List` as the real rows: never a separate
/// scroll container, which fights the navigation bar's large title. The shine is suppressed under
/// Reduce Motion.
struct SkeletonFileRows: View {
    let entries: [SkeletonEntry]

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            FileRowView(
                name: entry.name,
                isDirectory: entry.isDirectory,
                subtitle: entry.subtitle,
                kind: entry.isDirectory ? nil : ""
            )
            .redacted(reason: .placeholder)
            .shimmering()
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}

/// The grid's `GridCellView` stand ins, in the same grid as the real cells.
struct SkeletonGridCells: View {
    let entries: [SkeletonEntry]

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            GridCellView(name: entry.name, isDirectory: entry.isDirectory, kind: entry.isDirectory ? nil : "")
                .dsCard(padding: FileGridMetrics.cellPadding)
                .redacted(reason: .placeholder)
                .shimmering()
        }
    }
}

#Preview("Folder rows") {
    List {
        SkeletonFileRows(entries: [6, 12, 4].map { SkeletonEntry(name: SkeletonEntry.text($0), isDirectory: true) })
    }
}

#Preview("File rows") {
    List {
        SkeletonFileRows(entries: [8, 13, 6].map { SkeletonEntry(
            name: SkeletonEntry.text($0),
            subtitle: SkeletonEntry.text(9)
        ) })
    }
}

#Preview("Grid cells") {
    ScrollView {
        LazyVGrid(columns: FileGridMetrics.columns) {
            SkeletonGridCells(entries: [6, 12, 4, 9].map { SkeletonEntry(name: SkeletonEntry.text($0)) })
        }
    }
}
