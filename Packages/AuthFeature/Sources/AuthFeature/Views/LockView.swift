import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

public struct LockView: View {
    @Bindable var store: StoreOf<LockFeature>
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private enum Constants {
        #if os(iOS)
            static let badgeSize: CGFloat = .size96
            static let badgeFillOpacity: Double = .opacityWash
        #elseif os(macOS)
            static let sheetWidth: CGFloat = 520
            static let sheetHeight: CGFloat = 640
            static let cancelTrailing: CGFloat = .space32
            static let cancelBottom: CGFloat = .space24
        #endif
    }

    public init(store: StoreOf<LockFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            #if os(macOS)
                MacLockView(store: store) { actions }
            #elseif os(iOS)
                if horizontalSizeClass == .regular {
                    card
                } else {
                    fullScreen
                }
            #endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.Lock.screen)
        .sheet(
            item: $store.scope(state: \.signIn, action: \.signIn),
            onDismiss: { store.send(.signInSheetDismissed) },
            content: signInSheet
        )
        .dsAlert(isPresented: Binding(get: { store.signOut != .idle }, set: { _ in })) {
            DSAlertSheet(
                icon: IconKit.signOut,
                title: L10n.Settings.signOutAlertTitle,
                message: L10n.Settings.signOutMessage,
                confirmTitle: L10n.Settings.signOutButton,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                isConfirmLoading: store.signOut.isRunning,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.signOutConfirmed) },
                onDismiss: { store.send(.signOutCancelled) }
            )
        }
    }

    #if os(iOS)
        private var fullScreen: some View {
            VStack(spacing: .space24) {
                Spacer()
                header
                account
                Spacer()
                actions
            }
            .padding(.horizontal, .space24)
            .padding(.bottom, .space32)
            .frame(maxWidth: .sheetCardMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundGradient()
        }

        private var card: some View {
            ZStack {
                LoginCardBackground()
                ScrollView {
                    VStack(spacing: .space24) {
                        header
                        account
                        actions
                    }
                    .padding(.space32)
                    .background(DSSheetSurface(in: RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)))
                    .loginCard()
                    .containerRelativeFrame(.vertical, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }

        private var account: some View {
            VStack(spacing: .space12) {
                LockAccountCard(account: store.account)
                if let problem = store.problem {
                    Text(Self.message(for: problem, account: store.account))
                        .type(.body2(.semibold), style: .error)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Lock.problem)
                }
            }
        }

        private var header: some View {
            VStack(spacing: .space12) {
                IconKit.lock
                    .resizable()
                    .scaledToFit()
                    .frame(width: .iconLarge, height: .iconLarge)
                    .foregroundStyle(Color.accentText)
                    .frame(width: Constants.badgeSize, height: Constants.badgeSize)
                    .background(Circle().fill(Color.accent.opacity(Constants.badgeFillOpacity)))
                    .accessibilityHidden(true)
                Text(L10n.Lock.title)
                    .type(.headline3, style: .primaryOnSurface)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.Lock.subtitle)
                    .type(.body2(.regular), style: .secondary)
                    .multilineTextAlignment(.center)
            }
        }
    #endif

    private var actions: some View {
        VStack(spacing: .space8) {
            if store.shouldUnlockWithSSO {
                DSButton(
                    L10n.Login.ssoButton,
                    icon: IconKit.person,
                    style: .primary,
                    size: Self.unlockButtonSize,
                    isLoading: store.ssoPhase == .signingIn
                ) {
                    store.send(.ssoButtonTapped)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Lock.unlockButton)
            } else {
                DSButton(L10n.Lock.signIn, style: .primary, size: Self.unlockButtonSize) {
                    store.send(.signInButtonTapped)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Lock.unlockButton)
            }
            DSButton(L10n.Settings.signOutButton, style: .ghost) {
                store.send(.signOutButtonTapped)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Lock.signOutButton)
        }
        .disabled(store.isBusy)
    }

    private static var unlockButtonSize: DSButtonSize {
        #if os(macOS)
            .medium
        #elseif os(iOS)
            .large
        #endif
    }

    private func signInSheet(_ loginStore: StoreOf<LoginFormFeature>) -> some View {
        LoginFormView(
            store: loginStore,
            shouldAutoFocus: true,
            shouldFloodIntoApp: false,
            hasStepsSidebar: false
        )
        #if os(macOS)
        .frame(width: Constants.sheetWidth, height: Constants.sheetHeight)
        .overlay(alignment: .bottomTrailing) {
            Button(L10n.Common.cancel) { store.send(.signIn(.dismiss)) }
                .buttonStyle(.macDS(.secondary, size: .small))
                .keyboardShortcut(.cancelAction)
                .padding(.trailing, Constants.cancelTrailing)
                .padding(.bottom, Constants.cancelBottom)
        }
        #endif
    }

    static func message(for problem: LockFeature.Problem, account: AccountSummary) -> String {
        switch problem {
        case let .signInFailed(error): LoginFormFeature.message(for: error)
        case .otherAccount: L10n.Lock.otherAccount(account.displayName)
        case .signOutFailed: L10n.Settings.accountChangeFailed
        }
    }
}

#Preview("SSO account") {
    LockView(store: Store(initialState: .preview(authMode: .oidc)) { LockFeature() })
}

#Preview("Password account") {
    LockView(store: Store(initialState: .preview(authMode: .local)) { LockFeature() })
}

#Preview("Signing in") {
    var state = LockFeature.State.preview(authMode: .oidc)
    state.ssoPhase = .signingIn
    return LockView(store: Store(initialState: state) { LockFeature() })
}

#Preview("Other account") {
    var state = LockFeature.State.preview(authMode: .oidc)
    state.problem = .otherAccount
    return LockView(store: Store(initialState: state) { LockFeature() })
}

#Preview("Sign in failed") {
    var state = LockFeature.State.preview(authMode: .local)
    state.problem = .signInFailed(.network("offline"))
    return LockView(store: Store(initialState: state) { LockFeature() })
}

#Preview("Confirm sign out") {
    var state = LockFeature.State.preview(authMode: .local)
    state.signOut = .confirming
    return LockView(store: Store(initialState: state) { LockFeature() })
}

#Preview("Card, password account") {
    LockView(store: Store(initialState: .preview(authMode: .local)) { LockFeature() })
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("Card, other account") {
    var state = LockFeature.State.preview(authMode: .oidc)
    state.problem = .otherAccount
    return LockView(store: Store(initialState: state) { LockFeature() })
        .environment(\.horizontalSizeClass, .regular)
}
