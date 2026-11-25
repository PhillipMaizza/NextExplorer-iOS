#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let lockMarkSize: CGFloat = .iconXSmall
        static let chipIconSize: CGFloat = .iconXSmall
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
                    EmptyView()
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
            .frame(height: .size32)
            .background(Capsule().fill(Color.macRow))
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

    #Preview("Signing in, dark") {
        var state = LockFeature.State.preview(authMode: .oidc)
        state.ssoPhase = .signingIn
        return LockView(store: Store(initialState: state) { LockFeature() })
            .previewCanvas(.settingsWindow)
            .environment(\.colorScheme, .dark)
    }
#endif
