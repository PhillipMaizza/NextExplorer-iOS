import CoreModels
import DesignSystem
import SwiftUI

struct LockAccountCard: View {
    let account: AccountSummary

    var body: some View {
        HStack(spacing: .space12) {
            AvatarView.person(account.displayName, size: .size48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: .space2) {
                Text(account.displayName)
                    .type(.body2(.semibold), style: .primaryOnSurface)
                    .lineLimit(1)
                if let server = account.serverSubtitle {
                    Text(server)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .lockCardSurface()
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    @ViewBuilder
    func lockCardSurface() -> some View {
        #if os(macOS)
            MacFormGroup {
                MacFormRow(label: { self }, control: { EmptyView() })
            }
        #elseif os(iOS)
            dsCard()
        #endif
    }
}

#Preview("Username and server") {
    LockAccountCard(account: LockFeature.State.preview(authMode: .oidc).account)
        .padding(.space16)
        .backgroundGradient()
}

#Preview("Server only") {
    var account = LockFeature.State.preview(authMode: .oidc).account
    account.username = ""
    return LockAccountCard(account: account)
        .padding(.space16)
        .backgroundGradient()
}
