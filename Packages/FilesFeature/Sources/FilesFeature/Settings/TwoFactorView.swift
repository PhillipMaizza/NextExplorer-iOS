import ComposableArchitecture
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let sectionSpacing: CGFloat = .space24
    static let contentSpacing: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space16
    static let qrSize: CGFloat = 200
    static let qrScale: CGFloat = 8
    static let qrPadding: CGFloat = .space12
    static let qrCornerRadius: CGFloat = .radiusCard
    static let rowIconSize: CGFloat = .iconSmall
    static let codeColumns = 2
}

/// Turn two-factor authentication on or off for the signed in account, mirroring the web
/// client's two factor settings.
struct TwoFactorView: View {
    @Bindable var store: StoreOf<TwoFactorFeature>
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                switch store.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case let .failed(message):
                    DSErrorCard(message)
                    RetryLinkButton { store.send(.retryTapped) }
                case .off:
                    offSection
                case let .on(recoveryCodesLeft):
                    onSection(recoveryCodesLeft: recoveryCodesLeft)
                case let .enrolling(setup):
                    enrollingSection(setup)
                case let .showingRecoveryCodes(codes):
                    recoveryCodesSection(codes)
                }
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.contentSpacing)
        }
        .backgroundGradient()
        .navigationTitle(L10n.TwoFactor.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { store.send(.task) }
    }

    // MARK: - Phases

    private var offSection: some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            intro(L10n.TwoFactor.offTitle, L10n.TwoFactor.offIntro)
            errorCard
            DSButton(L10n.TwoFactor.turnOnButton, style: .primary, isLoading: store.isWorking) {
                store.send(.turnOnTapped)
            }
            .formActionAlignment()
        }
    }

    private func onSection(recoveryCodesLeft: Int) -> some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            intro(L10n.TwoFactor.onTitle, L10n.TwoFactor.recoveryCodesLeft(recoveryCodesLeft))
            errorCard
            if let prompt = store.passwordPrompt {
                passwordPrompt(prompt)
            } else {
                DSButton(L10n.TwoFactor.newCodesButton, style: .secondary) {
                    store.send(.newRecoveryCodesTapped)
                }
                .formActionAlignment()
                DSButton(L10n.TwoFactor.turnOffButton, style: .tertiary) {
                    store.send(.turnOffTapped)
                }
                .formActionAlignment()
            }
        }
    }

    private func enrollingSection(_ setup: TwoFactorSetup) -> some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            Text(L10n.TwoFactor.enrollIntro).type(.body3(.regular), style: .secondary)
            QRCodeView(text: setup.uri, accessibilityLabel: L10n.TwoFactor.qrAccessibilityLabel)
                .frame(maxWidth: .infinity)
            LabeledField(L10n.TwoFactor.keyLabel, uppercased: false) {
                HStack {
                    Text(setup.secret)
                        .type(.body2(.regular), style: .primaryOnSurface)
                        .textSelection(.enabled)
                    Spacer()
                    Button { PlatformPasteboard.copy(setup.secret) } label: {
                        IconKit.copy.accessibilityLabel(L10n.TwoFactor.copyKeyAccessibilityLabel)
                    }
                    .buttonStyle(.plain)
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
            errorCard
            DSButton(L10n.TwoFactor.confirmButton, style: .primary, isLoading: store.isWorking) {
                store.send(.confirmTapped)
            }
            .disabled(store.code.count != TwoFactorFeature.State.codeLength)
            .formActionAlignment()
            DSButton(L10n.Common.cancel, style: .tertiary) {
                store.send(.cancelSetupTapped)
            }
            .formActionAlignment()
        }
    }

    private func recoveryCodesSection(_ codes: [String]) -> some View {
        let text = codes.joined(separator: "\n")
        return VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            intro(L10n.TwoFactor.recoveryTitle, L10n.TwoFactor.recoveryIntro)
            Card {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: Metrics.codeColumns),
                    spacing: .space8
                ) {
                    ForEach(codes, id: \.self) { code in
                        Text(code)
                            .type(.body2(.regular), style: .primaryOnSurface)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                }
            }
            DSButton(L10n.TwoFactor.copyCodesButton, style: .secondary) {
                PlatformPasteboard.copy(text)
            }
            .formActionAlignment()
            ShareLink(item: text) {
                Text(L10n.TwoFactor.shareCodesButton).type(.label3, style: .link)
            }
            DSButton(L10n.TwoFactor.recoveryDoneButton, style: .primary) {
                store.send(.recoveryCodesDoneTapped)
            }
            .formActionAlignment()
        }
    }

    private func passwordPrompt(_ prompt: TwoFactorFeature.PasswordPrompt) -> some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            Text(prompt.action == .turnOff ? L10n.TwoFactor.passwordTurnOffIntro : L10n.TwoFactor.passwordNewCodesIntro)
                .type(.body3(.regular), style: .secondary)
            LabeledField(L10n.TwoFactor.passwordField, uppercased: false) {
                DSSecureField(L10n.TwoFactor.passwordField, text: Binding(get: { prompt.password }, set: { store.send(.passwordChanged($0)) }))
                    .credentialContentType(.password)
            }
            DSButton(
                L10n.TwoFactor.passwordConfirmButton,
                style: prompt.action == .turnOff ? .secondary : .primary,
                isLoading: store.isWorking
            ) {
                store.send(.passwordPromptConfirmed)
            }
            .disabled(!store.isPasswordPromptConfirmEnabled)
            .formActionAlignment()
            DSButton(L10n.Common.cancel, style: .tertiary) {
                store.send(.passwordPromptCancelled)
            }
            .formActionAlignment()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var errorCard: some View {
        if let message = store.errorMessage {
            DSErrorCard(message)
        }
    }

    private func intro(_ title: String, _ message: String) -> some View {
        Card {
            HStack(alignment: .top, spacing: .space8) {
                IconKit.shield
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                    .padding(.top, .space2)
                VStack(alignment: .leading, spacing: .space4) {
                    Text(title).type(.body2(.semibold), style: .primaryOnSurface)
                    Text(message).type(.body3(.regular), style: .secondary)
                }
            }
        }
    }
}

/// Draws `text` as a QR code. Built once, off the main thread, since Core Image is not free
/// and the view redraws as the code is typed.
private struct QRCodeView: View {
    let text: String
    let accessibilityLabel: String
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(width: Metrics.qrSize, height: Metrics.qrSize)
        .padding(Metrics.qrPadding)
        .background(RoundedRectangle(cornerRadius: Metrics.qrCornerRadius).fill(Color.white))
        .accessibilityLabel(accessibilityLabel)
        .task(id: text) {
            image = await Self.render(text)
        }
    }

    private static func render(_ text: String) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(text.utf8)
            filter.correctionLevel = "M"
            guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: Metrics.qrScale, y: Metrics.qrScale)) else {
                return nil
            }
            return CIContext().createCGImage(output, from: output.extent)
        }.value
    }
}

private enum PreviewFixtures {
    static let serverURL = URL(string: "https://nextexplorer.example.com")!
    static let setup = TwoFactorSetup(secret: "JBSWY3DPEHPK3PXP", uri: "otpauth://totp/NextExplorer:alice?secret=JBSWY3DPEHPK3PXP&issuer=NextExplorer")
    static let codes = ["2HSMP-G9ZSJ", "K3QWE-7RTYU", "ABCDE-FGHJK", "MNPQR-STUVW", "XY234-56789", "ZZ2AA-3BB44", "CC5DD-6EE77", "FF8GG-9HH22"]

    @MainActor
    static func view(_ state: TwoFactorFeature.State) -> some View {
        NavigationStack {
            TwoFactorView(store: Store(initialState: state) { EmptyReducer() })
        }
    }
}

#Preview("Loading") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .loading)) }
#Preview("Failed") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .failed("Couldn't reach the server."))) }
#Preview("Off") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .off)) }
#Preview("On") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .on(recoveryCodesLeft: 8))) }
#Preview("Enrolling") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .enrolling(PreviewFixtures.setup))) }
#Preview("Enrolling, wrong code") {
    PreviewFixtures.view({
        var state = TwoFactorFeature.State(serverURL: PreviewFixtures.serverURL, phase: .enrolling(PreviewFixtures.setup))
        state.errorMessage = "That code didn't match."
        return state
    }())
}

#Preview("Recovery codes") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .showingRecoveryCodes(PreviewFixtures.codes))) }
#Preview("Turn off, password") {
    PreviewFixtures.view({
        var state = TwoFactorFeature.State(serverURL: PreviewFixtures.serverURL, phase: .on(recoveryCodesLeft: 8))
        state.passwordPrompt = .init(action: .turnOff)
        return state
    }())
}

#Preview("New codes, wrong password") {
    PreviewFixtures.view({
        var state = TwoFactorFeature.State(serverURL: PreviewFixtures.serverURL, phase: .on(recoveryCodesLeft: 2))
        state.passwordPrompt = .init(action: .newRecoveryCodes)
        state.errorMessage = "Password is incorrect."
        return state
    }())
}
