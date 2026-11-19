#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let expiredOpacity: Double = 0.45
        static let audienceGlyphSize: CGFloat = .iconXSmall
        static let sharerAvatarSize: CGFloat = .size20
    }

    /// The Name cell: an item's icon and name, or for a share under it, who it reaches with its
    /// label beside. Fades once expired.
    struct MacSharedNameCell: View {
        let row: MacSharedRow
        let isExpired: Bool

        var body: some View {
            HStack(spacing: .space8) {
                if let share = row.child {
                    MacTableFolderIcon(
                        image: share.audienceIcon,
                        tint: Color.secondaryDS,
                        isFilled: false,
                        size: Metrics.audienceGlyphSize
                    )
                    .frame(width: MacBrowseTableMetrics.iconSize)
                    .accessibilityHidden(true)
                    Text(share.audienceTitle)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let label = share.trimmedLabel {
                        Text(label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    icon
                    Text(row.item.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .opacity(isExpired ? Metrics.expiredOpacity : 1)
        }

        /// Decorative: the name already says what the item is.
        private var icon: some View {
            Group {
                if row.item.shares[0].isDirectory {
                    MacTableFolderIcon(image: IconKit.folderFill, tint: Color.accent)
                } else {
                    FileTypeIcon(kind: (row.item.name as NSString).pathExtension)
                        .frame(width: MacBrowseTableMetrics.iconSize, height: MacBrowseTableMetrics.iconSize)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// The Expires cell: the date, the day countdown in the warning colour inside the window, or
    /// Expired in red. Plain on a selected row, where the colours would not read on the highlight.
    struct MacSharedExpiryCell: View {
        let expiresAt: Date?
        let notice: SharedFeature.ExpiryNotice?
        let dateFormat: DateDisplayFormat

        @Environment(\.backgroundProminence) private var prominence

        private var text: String {
            switch notice {
            case .expired: L10n.Shared.metaExpired
            case let .daysLeft(days): L10n.Shared.daysLeft(days)
            case nil: expiresAt.map { dateFormat.string(from: $0) } ?? L10n.Common.never
            }
        }

        var body: some View {
            Text(text)
                .lineLimit(1)
                .fontWeight(notice == nil ? .regular : .semibold)
                .foregroundStyle(
                    prominence == .increased
                        ? AnyShapeStyle(.primary)
                        : AnyShapeStyle(SharedShareFacts.style(for: notice).color)
                )
        }
    }

    /// The Shared by cell: the sharer's avatar and name.
    struct MacSharedSharerCell: View {
        let name: String

        var body: some View {
            HStack(spacing: .space8) {
                AvatarView(displayName: name, size: Metrics.sharerAvatarSize, tint: Color.categorical(for: name))
                    .accessibilityHidden(true)
                Text(name).lineLimit(1)
            }
        }
    }

    /// Redacted and shimmering per cell while the segment's first page loads, as
    /// `MacBrowseTableSkeleton` does.
    struct MacSharedPlaceholderCell: ViewModifier {
        let isActive: Bool

        func body(content: Content) -> some View {
            if isActive {
                content
                    .redacted(reason: .placeholder)
                    .shimmering()
            } else {
                content
            }
        }
    }

    private let previewItem = SharedFeature.Item(
        id: "personal:Work/Team Roadmap",
        name: "Team Roadmap",
        location: "Work",
        shares: [
            .previewCard(isDirectory: true, target: .users, sourcePath: "Work/Team Roadmap"),
            .previewCard(isDirectory: true, sourcePath: "Work/Team Roadmap"),
        ],
        badges: [],
        isExpired: false
    )

    #Preview("Cells") {
        VStack(alignment: .leading, spacing: .space12) {
            MacSharedNameCell(row: MacSharedRow(item: previewItem, expiringShare: nil), isExpired: false)
            MacSharedNameCell(
                row: MacSharedRow(item: previewItem, child: previewItem.shares[0], expiringShare: nil),
                isExpired: false
            )
            MacSharedNameCell(
                row: MacSharedRow(item: previewItem, child: previewItem.shares[1], expiringShare: nil),
                isExpired: true
            )
            MacSharedExpiryCell(expiresAt: nil, notice: nil, dateFormat: .system)
            MacSharedExpiryCell(expiresAt: Date(), notice: .daysLeft(3), dateFormat: .system)
            MacSharedExpiryCell(expiresAt: Date(), notice: .expired, dateFormat: .system)
            MacSharedSharerCell(name: "Anna Moreau")
        }
        .padding()
        .previewCanvas(.control)
    }

    #Preview("Cells: dark") {
        VStack(alignment: .leading, spacing: .space12) {
            MacSharedNameCell(row: MacSharedRow(item: previewItem, expiringShare: nil), isExpired: false)
            MacSharedExpiryCell(expiresAt: Date(), notice: .daysLeft(1), dateFormat: .system)
            MacSharedSharerCell(name: "Jonas Keller")
        }
        .padding()
        .background(Color.backgroundPrimary)
        .previewCanvas(.control)
        .preferredColorScheme(.dark)
    }
#endif
