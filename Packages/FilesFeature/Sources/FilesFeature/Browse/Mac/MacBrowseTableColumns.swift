#if os(macOS)
    import DesignSystem
    import SwiftUI

    enum MacBrowseTableMetrics {
        static let iconSize: CGFloat = .size20
        static let tileSize: CGFloat = .size24
        static let tileRadius: CGFloat = .radiusSmall
        static let thumbnailMaxPixels: CGFloat = .size96
        static let playGlyphSize: CGFloat = 10
        static let playGlyphShadow: CGFloat = 1
        static let badgeSize: CGFloat = .iconXSmall
        static let cutRowOpacity: Double = .opacityHalf
        static let nameColumnMinWidth: CGFloat = 220
        static let nameColumnCompactWidth: CGFloat = 120
        static let dateColumnWidth: CGFloat = 160
        static let sizeColumnWidth: CGFloat = 90
        static let kindColumnWidth: CGFloat = 90
    }

    struct MacBrowseTableColumns: Equatable {
        private enum Column {
            case date
            case size
            case kind
        }

        private let fit: MacTableColumnFit<Column>

        init(width: CGFloat) {
            fit = MacTableColumnFit(
                width: width,
                nameWidth: MacBrowseTableMetrics.nameColumnMinWidth,
                spacing: MacTableMetrics.columnSpacing,
                byPriority: [
                    (.date, MacBrowseTableMetrics.dateColumnWidth),
                    (.size, MacBrowseTableMetrics.sizeColumnWidth),
                    (.kind, MacBrowseTableMetrics.kindColumnWidth),
                ]
            )
        }

        var showsDate: Bool {
            fit.shows(.date)
        }

        var showsSize: Bool {
            fit.shows(.size)
        }

        var showsKind: Bool {
            fit.shows(.kind)
        }
    }

    extension View {
        func macBrowseTableWidth(_ width: Binding<CGFloat>) -> some View {
            frame(minWidth: .zero, maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width.wrappedValue = $0 }
        }
    }
#endif
