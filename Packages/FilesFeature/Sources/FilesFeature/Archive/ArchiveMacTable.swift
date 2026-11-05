#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = .iconSmall
        static let sizeColumnWidth: CGFloat = 90
    }

    /// The archive's current folder as a native table, like the Browse table: double click or
    /// Return opens a folder or previews a file.
    struct ArchiveMacTable: View {
        let rows: [ArchiveRow]
        /// The file being unpacked to open, shown with a spinner.
        let extractingRow: String?
        let entryTransition: Namespace.ID
        let onOpen: (ArchiveRow) -> Void

        var body: some View {
            Table(rows) {
                TableColumn(L10n.Sort.name) { row in
                    HStack(spacing: .space8) {
                        if row.isDirectory {
                            IconKit.folderFill.foregroundStyle(Color.accent)
                        } else {
                            FileTypeIcon(kind: (row.name as NSString).pathExtension)
                                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                                .matchedTransitionSource(id: row.name, in: entryTransition)
                        }
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                        if extractingRow == row.name {
                            MacSpinner()
                        }
                    }
                }
                TableColumn(L10n.Sort.size) { row in
                    Text(row.size.map { FileSizeFormat.string(Int64($0)) } ?? "")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(Metrics.sizeColumnWidth)
            }
            .contextMenu(forSelectionType: ArchiveRow.ID.self, menu: { _ in }, primaryAction: { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                    onOpen(row)
                }
            })
        }
    }

    private struct ArchiveMacTablePreview: View {
        @Namespace private var namespace
        let rows: [ArchiveRow]
        var extractingRow: String?

        var body: some View {
            ArchiveMacTable(rows: rows, extractingRow: extractingRow, entryTransition: namespace, onOpen: { _ in })
                .previewCanvas(.table)
        }
    }

    #Preview("Entries") {
        ArchiveMacTablePreview(rows: [
            ArchiveRow(name: "Photos", isDirectory: true, size: nil),
            ArchiveRow(name: "notes.txt", isDirectory: false, size: 2_048),
            ArchiveRow(name: "beach.jpg", isDirectory: false, size: 2_400_000),
        ], extractingRow: "beach.jpg")
    }

    #Preview("Empty") {
        ArchiveMacTablePreview(rows: [])
    }
#endif
