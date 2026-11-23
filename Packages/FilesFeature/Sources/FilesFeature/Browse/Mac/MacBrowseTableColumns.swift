#if os(macOS)
    import DesignSystem
    import SwiftUI

    enum MacBrowseTableMetrics {
        static let iconSize: CGFloat = .size20
        static let tileSize: CGFloat = 26
        static let tileRadius: CGFloat = 7
        static let thumbnailMaxPixels: CGFloat = .size96
        static let playGlyphSize: CGFloat = 10
        static let playGlyphShadow: CGFloat = 1
        static let badgeSize: CGFloat = .iconXSmall
        static let cutRowOpacity: Double = 0.5
        static let nameColumnMinWidth: CGFloat = 220
        static let nameColumnCompactWidth: CGFloat = 120
        static let dateColumnWidth: CGFloat = 160
        static let sizeColumnWidth: CGFloat = 90
        static let kindColumnWidth: CGFloat = 90
    }

    struct MacBrowseTableColumns: Equatable {
        let showsDate: Bool
        let showsSize: Bool
        let showsKind: Bool

        init(width: CGFloat) {
            typealias Widths = MacBrowseTableMetrics
            let gap = MacTableMetrics.columnSpacing
            let withDate = Widths.nameColumnMinWidth + gap + Widths.dateColumnWidth
            let withSize = withDate + gap + Widths.sizeColumnWidth
            showsDate = width >= withDate
            showsSize = width >= withSize
            showsKind = width >= withSize + gap + Widths.kindColumnWidth
        }
    }

    extension View {
        func macBrowseTableWidth(_ width: Binding<CGFloat>) -> some View {
            frame(minWidth: .zero, maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width.wrappedValue = $0 }
        }
    }
#endif
