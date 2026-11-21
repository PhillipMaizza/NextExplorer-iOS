import SwiftUI

/// Left to right wrapping layout: lays each subview after the previous one on the same row
/// until it no longer fits the proposed width, then drops to the next row. For chip/tag
/// groups whose count isn't known ahead of time.
public struct DSFlowLayout: Layout {
    private let horizontalSpacing: CGFloat
    private let verticalSpacing: CGFloat
    private let isRowCentered: Bool

    public init(horizontalSpacing: CGFloat = 4, verticalSpacing: CGFloat = 4, isRowCentered: Bool = false) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.isRowCentered = isRowCentered
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + horizontalSpacing + size.width > maxWidth {
                totalHeight += rowHeight + verticalSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? horizontalSpacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) {
        var rows: [[(subview: LayoutSubview, size: CGSize)]] = [[]]
        var rowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + horizontalSpacing + size.width > bounds.width {
                rows.append([])
                rowWidth = 0
            }
            rowWidth += (rowWidth > 0 ? horizontalSpacing : 0) + size.width
            rows[rows.count - 1].append((subview, size))
        }
        var y = bounds.minY
        for row in rows {
            let width = row.map(\.size.width).reduce(0, +) + horizontalSpacing * CGFloat(max(row.count - 1, 0))
            var x = isRowCentered ? bounds.minX + max(bounds.width - width, 0) / 2 : bounds.minX
            let height = row.map(\.size.height).max() ?? 0
            for item in row {
                item.subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + horizontalSpacing
            }
            y += height + verticalSpacing
        }
    }
}

#Preview {
    DSFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
        ForEach(
            ["Swift", "SwiftUI", "Composable Architecture", "iOS", "Layout", "Chips", "Design System", "Inter"],
            id: \.self
        ) { tag in
            Text(tag)
                .type(.caption(.semibold))
                .padding(.horizontal, .space8)
                .padding(.vertical, .space4)
                .background(Capsule().fill(Color.categorical(for: tag).opacity(0.16)))
                .foregroundStyle(Color.categorical(for: tag))
        }
    }
    .padding()
}

#Preview("Centered rows") {
    DSFlowLayout(horizontalSpacing: .space8, verticalSpacing: .space8, isRowCentered: true) {
        ForEach(["Create Folder", "Create File", "Paste 3 items"], id: \.self) { title in
            Text(title)
                .type(.label4)
                .padding(.horizontal, .space12)
                .padding(.vertical, .space8)
                .background(Capsule().fill(Color.backgroundSecondary))
        }
    }
    .frame(width: 280)
    .padding()
}
