#if os(macOS)
    import CoreGraphics
    import DesignSystem
    @testable import FilesFeature
    import Testing

    struct MacSharedTableColumnsTests {
        private typealias Column = MacSharedTableColumns.Column
        private let wide: CGFloat = 2000
        private let byMeColumns: [Column] = [.audience, .expires, .lastOpened, .downloads]
        private let withMeColumns: [Column] = [.sharer, .expires, .received]

        @Test
        func aWideTableShowsEveryColumnOfItsSegment() {
            let byMe = MacSharedTableColumns(width: wide, isByMe: true)
            let withMe = MacSharedTableColumns(width: wide, isByMe: false)

            #expect(byMeColumns.allSatisfy(byMe.shows))
            #expect(![Column.sharer, .received].contains(where: byMe.shows))
            #expect(withMeColumns.allSatisfy(withMe.shows))
            #expect(![Column.audience, .lastOpened, .downloads].contains(where: withMe.shows))
        }

        @Test
        func aNarrowTableKeepsTheNameAndDropsTheLeastUsefulColumnsFirst() {
            let tooNarrow = MacSharedTableColumns(width: MacBrowseTableMetrics.nameColumnMinWidth, isByMe: true)
            let expiresOnly = MacSharedTableColumns(
                width: MacBrowseTableMetrics.nameColumnMinWidth + MacTableMetrics.columnSpacing + 130,
                isByMe: true
            )

            #expect(!byMeColumns.contains(where: tooNarrow.shows))
            #expect(expiresOnly.shows(.expires))
            #expect(![Column.audience, .lastOpened, .downloads].contains(where: expiresOnly.shows))
        }
    }
#endif
