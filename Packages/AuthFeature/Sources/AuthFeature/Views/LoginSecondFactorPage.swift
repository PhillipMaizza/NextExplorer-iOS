import AuthClient
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The step after a right password on an account that asks for a code: the authenticator code or
/// one recovery code, sent as typed. The shape is never checked here, the server decides.
struct LoginSecondFactorPage: View {
    @Bindable var store: StoreOf<LoginFormFeature>
    let horizontalSizeClass: UserInterfaceSizeClass?
    /// The Verify button's rect in the sign in space, so the accent flood after a successful code
    /// grows out of this button's center, as it does from "Log In" on the password page.
    @Binding var submitButtonRect: CGRect
    @FocusState private var isCodeFocused: Bool

    private enum Constants {
        static let checkmarkSize: CGFloat = .iconSmall
        static let autoFocusDelay: Duration = .seconds(0.4)
        static let recoveryCodePlaceholder = "XXXXX-XXXXX"
        #if os(macOS)
            static var titleType: Typography.TextType {
                .headline1
            }
        #else
            static var titleType: Typography.TextType {
                .headline3
            }
        #endif
    }

    private var isSubmitEnabled: Bool {
        !store.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.submitPhase == .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
                LoginBackBar(title: nil) { store.send(.secondFactorBackButtonTapped) }
            #endif

            ScrollView {
                VStack(alignment: .leading, spacing: .space24) {
                    #if os(macOS)
                        MacLoginPageHeader(host: store.host, title: nil) {
                            store.send(.secondFactorBackButtonTapped)
                        }
                    #endif

                    VStack(alignment: .leading, spacing: .space8) {
                        Text(L10n.Login.codeTitle)
                            .type(Constants.titleType)
                        Text(store.codeMode == .authenticator
                            ? L10n.Login.codeIntroAuthenticator
                            : L10n.Login.codeIntroRecovery)
                            .type(.body2(.regular), style: .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    codeInput

                    verifyButton

                    codeModeButton

                    if let errorMessage = store.errorMessage, !errorMessage.isEmpty {
                        LoginErrorNote(message: errorMessage)
                    }

                    #if os(iOS)
                        LoginDiagnosticsButton(diagnostics: store.diagnostics)
                    #endif
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, .space16)
                .padding(.top, .space16)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background { LoginPageSurface(horizontalSizeClass: horizontalSizeClass) }
        .onChange(of: store.codeMode) { _, _ in
            isCodeFocused = true
        }
        // The keyboard leaves before the button collapses, so the button is where the flood starts,
        // and comes back once a failed check has settled so the next attempt needs no extra tap.
        .onChange(of: store.submitPhase) { _, phase in
            switch phase {
            case .submitting: isCodeFocused = false
            case .idle: isCodeFocused = true
            case .success, .failure: break
            }
        }
        .task {
            try? await DSMotion.waitForStep(Constants.autoFocusDelay)
            guard !Task.isCancelled else { return }
            isCodeFocused = true
        }
    }

    private var codeModeTitle: String {
        store.codeMode == .authenticator ? L10n.Login.codeUseRecovery : L10n.Login.codeUseAuthenticator
    }

    private var codeModeButton: some View {
        #if os(macOS)
            Button(codeModeTitle) { store.send(.toggleCodeModeTapped) }
                .buttonStyle(.macDS(.tertiary, size: .small))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(AccessibilityIdentifiers.Login.codeModeButton)
        #else
            DSButton(codeModeTitle, style: .ghost, size: .small) {
                store.send(.toggleCodeModeTapped)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Login.codeModeButton)
        #endif
    }

    private var codeBinding: Binding<String> {
        Binding(get: { store.code }, set: { store.send(.codeChanged($0)) })
    }

    @ViewBuilder
    private var codeInput: some View {
        switch store.codeMode {
        case .authenticator:
            DSCodeBoxes(
                code: codeBinding,
                isFocused: $isCodeFocused,
                length: LoginFormFeature.authenticatorCodeLength,
                isInvalid: store.errorMessage != nil,
                accessibilityLabel: L10n.Login.codeField,
                accessibilityIdentifier: AccessibilityIdentifiers.Login.codeField
            )
        case .recovery:
            DSFieldContainer(label: L10n.Login.codeField, icon: IconKit.key, isFocused: isCodeFocused) {
                TextField(
                    text: codeBinding,
                    prompt: Text(verbatim: Constants.recoveryCodePlaceholder).foregroundStyle(Color.secondaryText)
                ) {
                    EmptyView()
                }
                .textFieldStyle(.plain)
                .type(.body1(.regular))
                .tint(Color.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .onSubmit { store.send(.codeSubmitButtonTapped) }
                .focused($isCodeFocused)
                .accessibilityIdentifier(AccessibilityIdentifiers.Login.codeField)
            }
        }
    }

    private var verifyButton: some View {
        let phase = store.submitPhase
        let isCollapsed = phase != .idle
        return DSAnimatedButton(
            phase: phase,
            isCollapsed: isCollapsed,
            style: phase == .failure ? .failure : .primary,
            size: .medium,
            isHitEnabled: !isCollapsed,
            action: { store.send(.codeSubmitButtonTapped) }
        ) {
            ZStack {
                switch phase {
                case .idle:
                    Text(L10n.Login.codeSubmit)
                        .type(.label3)
                        .foregroundStyle(Color.onAccent)
                case .submitting:
                    DSSpinner(color: .onAccent)
                case .success:
                    IconKit.checkmark
                        .resizable()
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .foregroundStyle(Color.onAccent)
                        .bold()
                case .failure:
                    IconKit.close
                        .resizable()
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .foregroundStyle(.white)
                        .bold()
                }
            }
        }
        .disabled(!isSubmitEnabled && phase == .idle)
        .accessibilityIdentifier(AccessibilityIdentifiers.Login.codeSubmitButton)
        // The phase rides along so the rect is measured again at every phase change. The page slides
        // in from the side, and a rect taken mid slide would otherwise never be corrected, because
        // nothing later moves the button: the flood would grow from off center.
        .onGeometryChange(
            for: MeasuredButton.self,
            of: { MeasuredButton(rect: $0.frame(in: .named(LoginCoordinateSpace.root)), phase: phase) }
        ) { measured in
            if measured.rect != .zero {
                submitButtonRect = measured.rect
            }
        }
    }

    private struct MeasuredButton: Equatable {
        let rect: CGRect
        let phase: LoginFormFeature.SubmitPhase
    }
}

#if DEBUG
    private enum PreviewConstants {
        static let host = "192.168.1.187:3663"
        static let sampleCode = "123456"
        static let sampleRecoveryCode = "2HSMP-G9ZSJ"
    }

    @MainActor
    private func previewPage(
        _ state: LoginFormFeature.State,
        sizeClass: UserInterfaceSizeClass = .compact
    ) -> some View {
        LoginSecondFactorPage(
            store: Store(initialState: state) { LoginFormFeature() },
            horizontalSizeClass: sizeClass,
            submitButtonRect: .constant(.zero)
        )
    }

    #Preview("Empty") {
        previewPage(LoginFormFeature.State(currentPage: .secondFactor, scheme: .http, host: PreviewConstants.host))
    }

    #Preview("Code typed") {
        previewPage(LoginFormFeature.State(
            currentPage: .secondFactor, scheme: .http, host: PreviewConstants.host, code: PreviewConstants.sampleCode
        ))
    }

    #Preview("Verifying") {
        previewPage(LoginFormFeature.State(
            currentPage: .secondFactor, scheme: .http, host: PreviewConstants.host,
            code: PreviewConstants.sampleCode, submitPhase: .submitting
        ))
    }

    #Preview("Wrong code") {
        var diagnostics = LoginDiagnostics()
        diagnostics.record("code: code rejected by the server", isProblem: true, at: .distantPast)
        var state = LoginFormFeature.State(
            currentPage: .secondFactor, scheme: .http, host: PreviewConstants.host,
            code: PreviewConstants.sampleCode, submitPhase: .failure, errorMessage: L10n.Login.errorInvalidCode
        )
        state.diagnostics = diagnostics
        return previewPage(state)
    }

    #Preview("Recovery code") {
        previewPage(LoginFormFeature.State(
            currentPage: .secondFactor, scheme: .http, host: PreviewConstants.host,
            code: PreviewConstants.sampleRecoveryCode, codeMode: .recovery
        ))
    }

    #Preview("Regular width") {
        previewPage(
            LoginFormFeature.State(currentPage: .secondFactor, scheme: .http, host: PreviewConstants.host),
            sizeClass: .regular
        )
    }
#endif
