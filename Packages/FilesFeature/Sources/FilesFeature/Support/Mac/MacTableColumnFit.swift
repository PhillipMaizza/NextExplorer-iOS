#if os(macOS)
    import CoreGraphics

    struct MacTableColumnFit<Column: Hashable>: Equatable {
        private let shown: Set<Column>

        init(width: CGFloat, nameWidth: CGFloat, spacing: CGFloat, byPriority: [(Column, CGFloat)]) {
            var used = nameWidth
            var shown: Set<Column> = []
            for (column, columnWidth) in byPriority {
                used += spacing + columnWidth
                guard used <= width else { break }
                shown.insert(column)
            }
            self.shown = shown
        }

        func shows(_ column: Column) -> Bool {
            shown.contains(column)
        }
    }
#endif
