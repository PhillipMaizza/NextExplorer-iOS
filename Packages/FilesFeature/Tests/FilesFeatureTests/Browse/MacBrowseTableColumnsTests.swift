#if os(macOS)
    import CoreGraphics
    import DesignSystem
    @testable import FilesFeature
    import Testing

    struct MacBrowseTableColumnsTests {
        private let gap = MacTableMetrics.columnSpacing

        @Test
        func columnsAppearInPriorityOrderAsTheTableWidens() {
            let nameOnly = MacBrowseTableColumns(width: MacBrowseTableMetrics.nameColumnMinWidth)
            let withDate = MacBrowseTableColumns(
                width: MacBrowseTableMetrics.nameColumnMinWidth + gap + MacBrowseTableMetrics.dateColumnWidth
            )
            let all = MacBrowseTableColumns(width: .greatestFiniteMagnitude)

            #expect(!nameOnly.showsDate && !nameOnly.showsSize && !nameOnly.showsKind)
            #expect(withDate.showsDate && !withDate.showsSize && !withDate.showsKind)
            #expect(all.showsDate && all.showsSize && all.showsKind)
        }
    }
#endif
