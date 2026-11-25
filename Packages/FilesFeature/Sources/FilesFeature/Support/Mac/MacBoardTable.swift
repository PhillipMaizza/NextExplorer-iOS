#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    enum MacBoardTableMetrics {
        static let rowHeight: CGFloat = .size44
        static let cellHeight: CGFloat = rowHeight - .space8
    }

    extension View {
        func macBoardTableCell() -> some View {
            frame(height: MacBoardTableMetrics.cellHeight)
        }

        func macBoardTable() -> some View {
            tableStyle(.inset)
                .scrollContentBackground(.hidden)
                .alternatingRowBackgrounds(.disabled)
        }
    }

    private struct PreviewRow: Identifiable {
        let id: Int
        var name: String {
            "Row \(id)"
        }
    }

    private struct PreviewTable: View {
        @State private var selection: Set<Int> = [2]
        @State private var sortOrder = [KeyPathComparator(\PreviewRow.name)]

        var body: some View {
            Table((1 ... 8).map(PreviewRow.init), selection: $selection, sortOrder: $sortOrder) {
                TableColumn(L10n.Sort.name, value: \.name) { row in Text(row.name).macBoardTableCell() }
                TableColumn(L10n.Sort.size) { row in Text(verbatim: "\(row.id) KB").foregroundStyle(.secondary) }
                    .width(MacBrowseTableMetrics.sizeColumnWidth)
            }
            .macBoardTable()
            .padding()
            .frame(width: 520, height: 420)
            .background(Color.macCard)
        }
    }

    #Preview("Board table") {
        PreviewTable()
    }

    #Preview("Board table, dark") {
        PreviewTable()
            .preferredColorScheme(.dark)
    }
#endif
