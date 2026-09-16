import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let avatarSize: CGFloat = .size40
    static let rowSpacing: CGFloat = .space12
    static let authIconSize: CGFloat = .iconXSmall
    static let authIconChipSize: CGFloat = .size24
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space2
    static let tagBorderWidth: CGFloat = 1
}

/// One row in the admin user list: avatar, name (+ admin pill), email, and the sign-in method
/// chips.
struct UserRow: View {
    let user: User

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            AvatarView(displayName: user.displayName ?? user.username, size: Metrics.avatarSize)

            VStack(alignment: .leading, spacing: .space2) {
                HStack(spacing: .space8) {
                    Text(user.displayName ?? user.username)
                        .type(.body2(.semibold), style: .primaryOnSurface)
                        .lineLimit(1)
                    if user.isAdmin {
                        AdminTag()
                    }
                }
                if let email = user.email {
                    Text(email).type(.body3(.regular), style: .secondary).lineLimit(1).truncationMode(.middle)
                }
            }

            Spacer(minLength: .space8)

            AuthMethodChips(methods: user.authMethods)

            IconKit.chevronRight
                .resizable().scaledToFit()
                .foregroundStyle(Color.tertiaryDS)
                .frame(width: Metrics.authIconSize, height: Metrics.authIconSize)
        }
        .padding(.vertical, .space4)
        .contentShape(Rectangle())
    }
}

/// The accent outlined "ADMIN" pill, matching the one on the Settings profile card.
struct AdminTag: View {
    var body: some View {
        Text(L10n.UserManagement.badgeAdmin.uppercased())
            .type(.caption(.semibold), style: .link)
            .padding(.horizontal, Metrics.tagHorizontalPadding)
            .padding(.vertical, Metrics.tagVerticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusSmall)
                    .strokeBorder(Color.accent, lineWidth: Metrics.tagBorderWidth)
            )
    }
}

/// Overlapping circular chips, one per sign in method: key for a local password, cloud for
/// SSO. Mirrors the web list's login type cluster.
struct AuthMethodChips: View {
    let methods: [AuthMethod]

    var body: some View {
        HStack(spacing: -Metrics.authIconSize / 2) {
            ForEach(Array(methods.enumerated()), id: \.offset) { _, method in
                (method.isPassword ? IconKit.key : IconKit.cloud)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.authIconSize, height: Metrics.authIconSize)
                    .frame(width: Metrics.authIconChipSize, height: Metrics.authIconChipSize)
                    .background(Circle().fill(Color.backgroundPrimary))
                    .overlay(Circle().strokeBorder(Color.backgroundSecondary, lineWidth: 2))
            }
        }
    }
}
