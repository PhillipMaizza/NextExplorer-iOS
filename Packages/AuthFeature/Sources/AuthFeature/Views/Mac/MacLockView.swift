#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let lockMarkSize: CGFloat = .iconXSmall
        static let chipIconSize: CGFloat = .iconXSmall
        static let accountAvatarSize: CGFloat = .size32
        static let accountRowHeight: CGFloat = .size48
        static let lockBadgeSize: CGFloat = .size24
        static let lockBadgeFillOpacity: Double = 0.18
    }

    struct MacLockView<Actions: View>: View {
        let store: StoreOf<LockFeature>
        @ViewBuilder let actions: () -> Actions

        var body: some View {
            MacLoginShell {
                MacLoginSidebarFrame {
                    MacLoginStepRow(title: L10n.Lock.status, state: .current) {
                        IconKit.lock
                            .resizable()
                            .scaledToFit()
                            .bold()
                            .frame(width: Constants.lockMarkSize, height: Constants.lockMarkSize)
                            .foregroundStyle(Color.onAccent)
                    }
                } footer: {
                    accountList
                }
            } content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: .space24) {
                        hostChip
                        VStack(alignment: .leading, spacing: .space8) {
                            Text(L10n.Lock.title)
                                .type(.headline1)
                                .accessibilityAddTraits(.isHeader)
                            Text(L10n.Lock.subtitle)
                                .type(.body2(.regular), style: .secondary)
                        }
                        LockAccountCard(account: store.account)
                        if let problem = store.problem {
                            MacNote(LockView.message(for: problem, account: store.account), kind: .error)
                                .accessibilityIdentifier(AccessibilityIdentifiers.Lock.problem)
                        }
                        actions()
                    }
                    .padding(.vertical, .space40)
                    .containerRelativeFrame(.vertical, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .macLoginColumn()
            }
        }

        @ViewBuilder
        private var accountList: some View {
            let accounts = store.switchableAccounts
            if !accounts.isEmpty {
                VStack(alignment: .leading, spacing: .space4) {
                    Text(L10n.Settings.sectionAccounts)
                        .type(.caption(.semibold))
                        .foregroundStyle(Color.macChromeSecondary)
                        .padding(.horizontal, .space12)
                        .padding(.bottom, .space4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(accounts) { account in
                        MacLockAccountRow(account: account, isCurrent: account.id == store.account.id) {
                            store.send(.accountTapped(account.id))
                        }
                    }
                }
                .disabled(store.isBusy)
            }
        }

        private var hostChip: some View {
            HStack(spacing: .space8) {
                IconKit.lock
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.chipIconSize, height: Constants.chipIconSize)
                    .accessibilityHidden(true)
                Text(store.account.serverHost)
                    .type(.body3(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, .space12)
            .macMinHeight(.regular)
            .background(Capsule().fill(Color.macRow))
        }
    }

    private struct MacLockAccountRow: View {
        let account: AccountSummary
        let isCurrent: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: .space12) {
                    AvatarView.person(account.displayName, size: Constants.accountAvatarSize)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: .zero) {
                        Text(account.displayName)
                            .type(.body2(isCurrent ? .semibold : .regular))
                            .foregroundStyle(Color.macChromeText)
                            .lineLimit(1)
                        Text(account.serverHost)
                            .type(.caption(.regular))
                            .foregroundStyle(Color.macChromeSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: .zero)
                    if account.isLocked {
                        IconKit.lock
                            .resizable()
                            .scaledToFit()
                            .bold()
                            .frame(width: Constants.chipIconSize, height: Constants.chipIconSize)
                            .foregroundStyle(Color.accentText)
                            .frame(width: Constants.lockBadgeSize, height: Constants.lockBadgeSize)
                            .background(Circle().fill(Color.accent.opacity(Constants.lockBadgeFillOpacity)))
                            .accessibilityLabel(L10n.Lock.status)
                    }
                }
                .padding(.horizontal, .space12)
                .macMinHeight(points: Constants.accountRowHeight)
                .background {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                            .fill(Color.macSelection)
                            .elevation(.level1)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                            .fill(Color.macChromeHover)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        }
    }

    #Preview("SSO account") {
        LockView(store: Store(initialState: .preview(authMode: .oidc)) { LockFeature() })
            .previewCanvas(.settingsWindow)
    }

    #Preview("Password account") {
        LockView(store: Store(initialState: .preview(authMode: .local)) { LockFeature() })
            .previewCanvas(.settingsWindow)
    }

    #Preview("Other account") {
        var state = LockFeature.State.preview(authMode: .oidc)
        state.problem = .otherAccount
        return LockView(store: Store(initialState: state) { LockFeature() })
            .previewCanvas(.settingsWindow)
    }

    #Preview("Several accounts") {
        @Shared(.inMemory(AccountSummary.sharedKey)) var accounts: [AccountSummary] = []
        let current = LockFeature.State.preview(authMode: .local).account
        var other = current
        other.id = "other"
        other.username = "sam"
        other.isLocked = false
        $accounts.withLock { $0 = [current, other] }
        return LockView(store: Store(initialState: .preview(authMode: .local)) { LockFeature() })
            .previewCanvas(.settingsWindow)
    }

    #Preview("Signing in, dark") {
        var state = LockFeature.State.preview(authMode: .oidc)
        state.ssoPhase = .signingIn
        return LockView(store: Store(initialState: state) { LockFeature() })
            .previewCanvas(.settingsWindow)
            .environment(\.colorScheme, .dark)
    }
#endif
