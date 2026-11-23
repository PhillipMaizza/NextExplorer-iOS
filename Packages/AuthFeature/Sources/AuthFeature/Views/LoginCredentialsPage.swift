import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let checkmarkSize: CGFloat = .iconSmall
    static let ssoIconSize: CGFloat = .iconSmall
    #if os(macOS)
        static let identifierPrompt = L10n.Login.identifierField
        static let maskedPasswordPlaceholder = L10n.Login.passwordField
    #else
        static let identifierPrompt = "name@company.com"
        static let maskedPasswordPlaceholder = "••••••••"
    #endif
    /// Focusing the identifier the instant the page appears races its slide in: the field takes
    /// focus before its frame settles, and a keyboard AutoFill made then silently fails.
    /// Waiting out the page transition avoids that.
    static let identifierAutoFocusDelay: Duration = .seconds(0.4)
    static let dividerOpacity: Double = 0.35
}

/// The sign in form's second page: the server's name with a way back, then email and password,
/// SSO, or both, as the server offers them.
struct LoginCredentialsPage: View {
    private enum Field: Hashable {
        case identifier
        case password
    }

    let store: StoreOf<LoginFormFeature>
    let horizontalSizeClass: UserInterfaceSizeClass?
    let identifierShakeTrigger: CGFloat
    let passwordShakeTrigger: CGFloat
    let isIdentifierFieldInvalid: Bool
    let isPasswordFieldInvalid: Bool
    let displayedErrorMessage: String?
    /// Where each sign in button sits in `LoginCoordinateSpace.root`, the seed of its flood.
    @Binding var submitButtonRect: CGRect
    @Binding var ssoButtonRect: CGRect

    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
                LoginBackBar(title: store.host) { store.send(.backButtonTapped) }
            #endif

            ScrollView {
                VStack(alignment: .leading, spacing: .space24) {
                    #if os(macOS)
                        MacLoginPageHeader(host: store.host, title: L10n.Login.submit) {
                            store.send(.backButtonTapped)
                        }
                    #endif

                    if let summary = store.certificateInUse {
                        LoginCertificateStatus(summary: summary) {
                            focusedField = nil
                            store.send(.changeClientCertificateTapped)
                        }
                    }

                    if store.authStatus?.isLocalEnabled == true {
                        identifierField
                        passwordField

                        // After the fields on purpose: a conditional sibling *above* them shifts
                        // their position in the container and drops the keyboard's AutoFill session.
                        if store.scheme == .http {
                            #if os(macOS)
                                MacNote(L10n.Login.plaintextWarning, kind: .warning)
                            #else
                                DSInfoCard(L10n.Login.plaintextWarning)
                            #endif
                        }

                        continueButton
                    }

                    if store.authStatus?.isOIDCEnabled == true {
                        if isSSOOnly {
                            Text(L10n.Login.ssoOnlyNote)
                                .type(.body2(.regular), style: .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            orDivider
                        }
                        ssoButton
                        if store.certificateInUse != nil {
                            Text(L10n.Login.ssoClientCertificateNote)
                                .type(.body3(.regular), style: .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let errorMessage = displayedErrorMessage, !errorMessage.isEmpty {
                        LoginErrorNote(message: errorMessage)
                    }

                    #if os(iOS)
                        LoginDiagnosticsButton(diagnostics: store.diagnostics)
                    #endif
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, .space16)
                .padding(.top, .space32)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background { LoginPageSurface(horizontalSizeClass: horizontalSizeClass) }
    }

    private var identifierField: some View {
        DSFieldContainer(
            label: L10n.Login.identifierField,
            icon: IconKit.person,
            shakeTrigger: identifierShakeTrigger,
            isInvalid: isIdentifierFieldInvalid,
            isFocused: focusedField == .identifier
        ) {
            // Native `prompt:` rather than a ZStack placeholder overlay: a sibling view stacked
            // on the field is a documented AutoFill target resolution hazard.
            TextField(
                text: Binding(get: { store.identifier }, set: { store.send(.identifierChanged($0)) }),
                // `verbatim` so the email shaped placeholder isn't markdown/link inferred (iOS 18
                // renders an inferred email as a blue link, ignoring the prompt's own color).
                prompt: Text(verbatim: Constants.identifierPrompt).foregroundStyle(Color.secondaryText)
            ) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .type(.body1(.regular))
            .tint(Color.accent)
            .textContentType(.username)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier(AccessibilityIdentifiers.Login.identifierField)
            .focused($focusedField, equals: .identifier)
            .submitLabel(.next)
            .onSubmit { focusedField = .password }
            .task {
                try? await DSMotion.waitForStep(Constants.identifierAutoFocusDelay)
                guard !Task.isCancelled else { return }
                focusedField = .identifier
            }
        }
    }

    private var passwordField: some View {
        DSFieldContainer(
            label: L10n.Login.passwordField,
            icon: IconKit.lock,
            shakeTrigger: passwordShakeTrigger,
            isInvalid: isPasswordFieldInvalid,
            isFocused: focusedField == .password
        ) {
            HStack(spacing: .space8) {
                // Both fields stay mounted at all times: swapping SecureField/TextField in and
                // out via `if/else` tears down and rebuilds the underlying text input on every
                // reveal toggle, which drops the AutoFill session iOS (and any password manager)
                // had going for it. Toggling opacity and hit testing instead keeps one stable
                // field identity so AutoFill keeps working across a visibility toggle.
                ZStack(alignment: .leading) {
                    SecureField(
                        text: Binding(get: { store.password }, set: { store.send(.passwordChanged($0)) }),
                        prompt: Text(Constants.maskedPasswordPlaceholder).foregroundColor(Color.secondaryText)
                    ) {
                        EmptyView()
                    }
                    .opacity(store.isPasswordVisible ? 0 : 1)
                    .allowsHitTesting(!store.isPasswordVisible)
                    .accessibilityHidden(store.isPasswordVisible)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Login.passwordField)
                    // Only the field currently on screen may claim `.password`; both fields
                    // staying mounted with the same content type makes AutoFill's
                    // username/password pairing ambiguous and it silently declines to fill
                    // either (this is what broke password manager AutoFill).
                    .textContentType(store.isPasswordVisible ? nil : .password)

                    TextField(
                        text: Binding(get: { store.password }, set: { store.send(.passwordChanged($0)) }),
                        prompt: Text(Constants.maskedPasswordPlaceholder).foregroundColor(Color.secondaryText)
                    ) {
                        EmptyView()
                    }
                    .opacity(store.isPasswordVisible ? 1 : 0)
                    .allowsHitTesting(store.isPasswordVisible)
                    .accessibilityHidden(!store.isPasswordVisible)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Login.passwordFieldVisible)
                    .textContentType(store.isPasswordVisible ? .password : nil)
                }
                .textFieldStyle(.plain)
                .type(.body1(.regular))
                .tint(Color.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    guard isSubmitLocalEnabled, store.submitPhase == .idle else { return }
                    submit(.continueButtonTapped)
                }

                if focusedField == .password {
                    Button {
                        store.send(.togglePasswordVisibility)
                    } label: {
                        (store.isPasswordVisible ? IconKit.eyeSlash : IconKit.eye)
                            .foregroundStyle(Color.secondaryText)
                            .frame(minWidth: .size44, minHeight: .size44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressableButtonStyle())
                    .accessibilityLabel(store.isPasswordVisible ? L10n.Login.hidePassword : L10n.Login.showPassword)
                    .transition(.opacity)
                }
            }
            .animation(DSMotion.quickFade, value: focusedField)
        }
    }

    private var continueButton: some View {
        let phase = store.submitPhase
        let isCollapsed = phase != .idle
        return DSAnimatedButton(
            phase: phase,
            isCollapsed: isCollapsed,
            // `.primary` (accent) through success too, so the circle `AppView` grows out of
            // the collapsed button reads as the same object flooding the screen.
            style: phase == .failure ? .failure : .primary,
            size: .medium,
            isHitEnabled: !isCollapsed,
            action: { submit(.continueButtonTapped) }
        ) {
            ZStack {
                switch phase {
                case .idle:
                    Text(L10n.Login.submit)
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
        .disabled(!isSubmitLocalEnabled && phase == .idle)
        .accessibilityIdentifier(AccessibilityIdentifiers.Login.submitButton)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(LoginCoordinateSpace.root)) }) { newFrame in
            if newFrame != .zero {
                submitButtonRect = newFrame
            }
        }
        .animation(DSMotion.quickFade, value: isSubmitLocalEnabled)
    }

    private var orDivider: some View {
        HStack(spacing: .space12) {
            Rectangle().fill(Color.secondaryText.opacity(Constants.dividerOpacity)).frame(height: 1)
            Text(L10n.Login.orDivider)
                .type(.body2(.semibold), style: .secondary)
                .fixedSize()
            Rectangle().fill(Color.secondaryText.opacity(Constants.dividerOpacity)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var ssoButton: some View {
        let phase = store.oidcPhase
        let isCollapsed = phase != .idle
        return DSAnimatedButton(
            phase: phase,
            isCollapsed: isCollapsed,
            // Outline while idle/authenticating so it stays visually secondary to Continue, then
            // `.primary` (accent) on success so the collapsed circle is the same object the
            // accent flood grows out of, exactly like the password button collapses and floods.
            style: phase == .success || isSSOOnly ? .primary : .outline,
            size: .medium,
            isHitEnabled: !isCollapsed,
            action: { submit(.ssoButtonTapped) }
        ) {
            ZStack {
                switch phase {
                case .idle:
                    HStack(spacing: .space8) {
                        IconKit.person
                            .resizable()
                            .frame(width: Constants.ssoIconSize, height: Constants.ssoIconSize)
                        Text(L10n.Login.ssoButton)
                            .type(.label3)
                    }
                    .foregroundStyle(ssoLabelColor)
                case .authenticating:
                    DSSpinner(color: ssoLabelColor)
                case .success:
                    IconKit.checkmark
                        .resizable()
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .foregroundStyle(Color.onAccent)
                        .bold()
                }
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(LoginCoordinateSpace.root)) }) { newFrame in
            if newFrame != .zero {
                ssoButtonRect = newFrame
            }
        }
    }

    private var isSSOOnly: Bool {
        store.authStatus?.isLocalEnabled != true
    }

    private var ssoLabelColor: Color {
        isSSOOnly ? .onAccent : .primaryDS
    }

    private var isSubmitLocalEnabled: Bool {
        !store.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.password.isEmpty
    }

    /// Drops the keyboard first, so its reflow doesn't shift the button mid collapse, and for
    /// SSO so it doesn't stay up behind the web sign in sheet.
    private func submit(_ action: LoginFormFeature.Action) {
        let wasFocused = focusedField != nil
        focusedField = nil
        LoginKeyboard.send(action, to: store, afterDismissing: wasFocused)
    }
}

@MainActor
private func credentialsPreview(local: Bool, sso: Bool, error: String? = nil) -> some View {
    LoginCredentialsPage(
        store: Store(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "nextexplorer.example.com",
                authStatus: AuthStatus(localEnabled: local, oidcEnabled: sso)
            )
        ) { LoginFormFeature() },
        horizontalSizeClass: .compact,
        identifierShakeTrigger: 0,
        passwordShakeTrigger: 0,
        isIdentifierFieldInvalid: error != nil,
        isPasswordFieldInvalid: error != nil,
        displayedErrorMessage: error,
        submitButtonRect: .constant(.zero),
        ssoButtonRect: .constant(.zero)
    )
}

#Preview("Password") {
    credentialsPreview(local: true, sso: false)
}

#Preview("Password and SSO") {
    credentialsPreview(local: true, sso: true)
}

#Preview("SSO only") {
    credentialsPreview(local: false, sso: true)
}

#Preview("Error") {
    credentialsPreview(local: true, sso: false, error: L10n.Login.portHint)
}
