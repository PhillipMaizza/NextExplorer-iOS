import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// Shared layout constants for the admin user detail screen and its sheets. Split files under
/// `UserManagement/` alias this as `Metrics` so their bodies read unchanged.
enum UserDetailMetrics {
    static let avatarSize: CGFloat = .size56
    static let contentSpacing: CGFloat = .space24
    static let cardSpacing: CGFloat = .space12
    static let cardTitleSpacing: CGFloat = .space8
    static let cardPadding: CGFloat = .space16
    static let cardCornerRadius: CGFloat = .radiusCard
    static let horizontalPadding: CGFloat = .space16
    static let rowIconSize: CGFloat = .iconSmall
    static let lockedInfoIconSize: CGFloat = .iconXSmall
    static let volumeSheetSpacing: CGFloat = .space24
    static let volumeSheetMaxHeightFraction: CGFloat = 0.9
    static let badgeHorizontalPadding: CGFloat = .space8
    static let badgeVerticalPadding: CGFloat = .space2
}

private typealias Metrics = UserDetailMetrics

/// A section: an optional uppercase header over a rounded `backgroundSecondary` box. The
/// header sits outside the box so the tabs read as a list of labelled sections rather than
/// nested titled cards. Pass no title for a plain card (an intro blurb, a single note).
struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.cardTitleSpacing) {
            if let title {
                DSFieldLabel(title)
            }
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                content
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.backgroundSecondary))
        }
    }
}

struct AccessModeBadge: View {
    let mode: ShareAccessMode

    private var tint: Color {
        mode == .readonly ? .attention : .positive
    }

    var body: some View {
        Text(mode == .readonly ? L10n.AccessMode.readonly : L10n.AccessMode.readwrite)
            .type(.caption(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Metrics.badgeHorizontalPadding)
            .padding(.vertical, Metrics.badgeVerticalPadding)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}
