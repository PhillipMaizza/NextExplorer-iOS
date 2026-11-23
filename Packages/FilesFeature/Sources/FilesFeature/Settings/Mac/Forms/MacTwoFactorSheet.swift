#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let spacing: CGFloat = .space16
        static let statusTileSize: CGFloat = .size40
        static let statusIconSize: CGFloat = .size20
        static let qrSize: CGFloat = 108
        static let codeColumns = 2
        static let copyButtonSize: CGFloat = .size24
    }

    struct MacTwoFactorSheet: View {
        @Bindable var store: StoreOf<TwoFactorFeature>
        let onClose: () -> Void
        @FocusState private var isCodeFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                MacDialogHeading(title: title, message: message)
                content
                if let error = store.errorMessage {
                    MacNote(error, kind: .error)
                }
                buttons
            }
            .padding(.space24)
            .frame(width: MacFormSheetMetrics.width)
            .animation(DSMotion.stateFade, value: store.phase)
            .task { store.send(.task) }
        }

        private var title: String {
            if case .showingRecoveryCodes = store.phase {
                return L10n.TwoFactor.recoveryTitle
            }
            if store.passwordPrompt?.action == .newRecoveryCodes {
                return L10n.TwoFactor.newCodesButton
            }
            return L10n.TwoFactor.navigationTitle
        }

        private var message: String? {
            if let prompt = store.passwordPrompt {
                return prompt.action == .turnOff
                    ? L10n.TwoFactor.passwordTurnOffIntro
                    : L10n.TwoFactor
                        .passwordNewCodesIntro
            }
            switch store.phase {
            case .enrolling: return L10n.TwoFactor.enrollIntro
            case .showingRecoveryCodes: return L10n.TwoFactor.recoveryIntro
            case .loading, .failed, .off, .on: return nil
            }
        }

        @ViewBuilder
        private var content: some View {
            switch store.phase {
            case .loading:
                MacSpinner().frame(maxWidth: .infinity)
            case let .failed(message):
                MacNote(message, kind: .error)
            case .off:
                statusBox(
                    title: L10n.TwoFactor.offTitle,
                    detail: L10n.TwoFactor.offIntro,
                    fill: .macTagGrayFill,
                    tint: .macTagGray
                )
            case let .on(recoveryCodesLeft):
                if let prompt = store.passwordPrompt {
                    passwordField(prompt)
                } else {
                    statusBox(
                        title: L10n.TwoFactor.onTitle,
                        detail: L10n.TwoFactor.recoveryCodesLeft(recoveryCodesLeft),
                        fill: .macTagGreenFill,
                        tint: .macTagGreen
                    )
                }
            case let .enrolling(setup):
                enrollment(setup)
            case let .showingRecoveryCodes(codes):
                recoveryCodes(codes)
            }
        }

        @ViewBuilder
        private var buttons: some View {
            switch store.phase {
            case .loading:
                MacDialogButtons(confirmTitle: nil, cancelTitle: L10n.Common.close, onCancel: onClose) {}
            case .failed:
                MacDialogButtons(
                    confirmTitle: L10n.Common.retry,
                    cancelTitle: L10n.Common.close,
                    onCancel: onClose
                ) { store.send(.retryTapped) }
            case .off:
                MacDialogButtons(
                    confirmTitle: L10n.TwoFactor.turnOnButton,
                    isWorking: store.isWorking,
                    cancelTitle: L10n.Common.close,
                    onCancel: onClose
                ) { store.send(.turnOnTapped) }
            case .on:
                if let prompt = store.passwordPrompt {
                    passwordButtons(prompt)
                } else {
                    MacDialogButtons(
                        confirmTitle: L10n.Common.done,
                        cancelTitle: nil,
                        secondaryTitle: L10n.TwoFactor.newCodesButton,
                        onSecondary: { store.send(.newRecoveryCodesTapped) },
                        onCancel: onClose,
                        onConfirm: onClose
                    ) {
                        Button(L10n.TwoFactor.turnOffButton, role: .destructive) { store.send(.turnOffTapped) }
                            .buttonStyle(.macDS(.secondary))
                    }
                }
            case .enrolling:
                MacDialogButtons(
                    confirmTitle: L10n.TwoFactor.confirmButton,
                    isConfirmEnabled: store.code.count == TwoFactorFeature.State.codeLength,
                    isWorking: store.isWorking,
                    onCancel: { store.send(.cancelSetupTapped) }
                ) { store.send(.confirmTapped) }
            case let .showingRecoveryCodes(codes):
                let text = codes.joined(separator: "\n")
                HStack(spacing: .space8) {
                    Spacer()
                    Button(L10n.TwoFactor.copyCodesButton) { PlatformPasteboard.copy(text) }
                        .buttonStyle(.macDS(.secondary))
                    ShareLink(item: text) { Text(L10n.TwoFactor.shareCodesButton) }
                        .buttonStyle(.macDS(.secondary))
                    Button(L10n.TwoFactor.recoveryDoneButton) { store.send(.recoveryCodesDoneTapped) }
                        .buttonStyle(.macDS(.primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }

        private func statusBox(title: String, detail: String, fill: Color, tint: Color) -> some View {
            HStack(alignment: .top, spacing: .space12) {
                IconKit.shield
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.statusIconSize, height: Metrics.statusIconSize)
                    .foregroundStyle(tint)
                    .frame(width: Metrics.statusTileSize, height: Metrics.statusTileSize)
                    .background(RoundedRectangle(cornerRadius: .radiusControl, style: .continuous).fill(fill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .space4) {
                    Text(title).type(.body2(.semibold))
                    Text(detail)
                        .type(.body3(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: .zero)
            }
            .padding(.space16)
            .background(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous).fill(Color.macRow))
            .accessibilityElement(children: .combine)
        }

        private func enrollment(_ setup: TwoFactorSetup) -> some View {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                HStack(spacing: .space16) {
                    QRCodeView(
                        text: setup.uri,
                        accessibilityLabel: L10n.TwoFactor.qrAccessibilityLabel,
                        size: Metrics.qrSize
                    )
                    VStack(alignment: .leading, spacing: .space4) {
                        Text(L10n.TwoFactor.keyLabel).type(.body3(.semibold), style: .secondary)
                        HStack(spacing: .space8) {
                            Text(setup.secret)
                                .type(.body2(.regular))
                                .monospaced()
                                .textSelection(.enabled)
                            Button { PlatformPasteboard.copy(setup.secret) } label: {
                                IconKit.copy
                                    .frame(width: Metrics.copyButtonSize, height: Metrics.copyButtonSize)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabelWithTooltip(L10n.TwoFactor.copyKeyAccessibilityLabel)
                        }
                    }
                }
                DSCodeBoxes(
                    code: $store.code.sending(\.codeChanged),
                    isFocused: $isCodeFocused,
                    length: TwoFactorFeature.State.codeLength,
                    isInvalid: store.errorMessage != nil,
                    accessibilityLabel: L10n.TwoFactor.codeAccessibilityLabel,
                    accessibilityIdentifier: AccessibilityIdentifiers.Settings.twoFactorCodeField
                )
                .onAppear { isCodeFocused = true }
            }
        }

        private func recoveryCodes(_ codes: [String]) -> some View {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: Metrics.codeColumns),
                spacing: .space4
            ) {
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .type(.body2(.regular))
                        .monospaced()
                        .textSelection(.enabled)
                }
            }
            .padding(.space12)
            .background(RoundedRectangle(cornerRadius: .radiusControl, style: .continuous).fill(Color.macRow))
        }

        private func passwordField(_ prompt: TwoFactorFeature.PasswordPrompt) -> some View {
            Form {
                MacSettingsRow(L10n.TwoFactor.passwordField) {
                    MacSecureField(
                        L10n.TwoFactor.passwordField,
                        text: Binding(get: { prompt.password }, set: { store.send(.passwordChanged($0)) })
                    )
                    .textContentType(.password)
                }
            }
            .formStyle(.columns)
        }

        private func passwordButtons(_ prompt: TwoFactorFeature.PasswordPrompt) -> some View {
            HStack(spacing: .space8) {
                Spacer()
                if store.isWorking {
                    MacSpinner()
                }
                Button(L10n.Common.cancel) { store.send(.passwordPromptCancelled) }
                    .buttonStyle(.macDS(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(L10n.TwoFactor.passwordConfirmButton) { store.send(.passwordPromptConfirmed) }
                    .buttonStyle(.macDS(prompt.action == .turnOff ? .failure : .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.isPasswordPromptConfirmEnabled || store.isWorking)
            }
        }
    }

    private enum PreviewFixtures {
        static let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
        static let setup = TwoFactorSetup(
            secret: "JBSWY3DPEHPK3PXP",
            uri: "otpauth://totp/NextExplorer:alice?secret=JBSWY3DPEHPK3PXP&issuer=NextExplorer"
        )

        @MainActor
        static func sheet(
            _ phase: TwoFactorFeature.Phase,
            edit: (inout TwoFactorFeature.State) -> Void = { _ in }
        ) -> some View {
            var state = TwoFactorFeature.State(serverURL: serverURL, phase: phase)
            edit(&state)
            return MacTwoFactorSheet(store: Store(initialState: state) { EmptyReducer() }, onClose: {})
                .background(Color.macCard)
        }
    }

    #Preview("Loading") { PreviewFixtures.sheet(.loading) }
    #Preview("Failed") { PreviewFixtures.sheet(.failed("Couldn't reach the server.")) }
    #Preview("Off") { PreviewFixtures.sheet(.off) }
    #Preview("On") { PreviewFixtures.sheet(.on(recoveryCodesLeft: 8)) }
    #Preview("Enrolling") { PreviewFixtures.sheet(.enrolling(PreviewFixtures.setup)) }
    #Preview("Enrolling, wrong code") {
        PreviewFixtures.sheet(.enrolling(PreviewFixtures.setup)) { $0.errorMessage = "That code didn't match." }
    }

    #Preview("Recovery codes") {
        PreviewFixtures.sheet(.showingRecoveryCodes([
            "2HSMP-G9ZSJ", "K3QWE-7RTYU", "ABCDE-FGHJK", "MNPQR-STUVW",
            "XY234-56789", "ZZ2AA-3BB44", "CC5DD-6EE77", "FF8GG-9HH22",
        ]))
    }

    #Preview("Turn off, password") {
        PreviewFixtures.sheet(.on(recoveryCodesLeft: 8)) { $0.passwordPrompt = .init(action: .turnOff) }
    }

    #Preview("New codes, wrong password") {
        PreviewFixtures.sheet(.on(recoveryCodesLeft: 2)) {
            $0.passwordPrompt = .init(action: .newRecoveryCodes)
            $0.errorMessage = "Password is incorrect."
        }
    }
#endif
