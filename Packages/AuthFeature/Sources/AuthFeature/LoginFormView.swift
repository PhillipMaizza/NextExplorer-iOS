import AuthClient
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let pageTransitionSpringResponse: Double = 0.4
    static let pageTransitionSpringDamping: Double = 0.85
    static let contentFadeDuration: Double = 0.15
    static let quickFadeDuration: Double = 0.2
    static let navBarHeight: CGFloat = .size44
    static let navBarTitleHorizontalPadding: CGFloat = .size44
    static let backChevronSize: CGFloat = .iconSmall
    static let backChevronWeight: Font.Weight = .semibold
    static let checkmarkSize: CGFloat = .iconSmall
    /// How long after a failed Test Connection (once the button has morphed into the red X
    /// and the field has shaken) the error text waits before fading in.
    static let errorRevealDelay: Duration = .seconds(0.4)
    static let errorFadeDuration: Double = 0.3
    /// How long the email/password fields stay red-bordered after a login failure.
    static let invalidFieldsDuration: Duration = .seconds(2)
    static let logoSize: CGFloat = .size96
    static let credentialsLogoSize: CGFloat = .size56
    static let maskedPasswordPlaceholder = "••••••••"
    /// Focusing `identifierField` the instant the credentials page appears races the page-slide
    /// transition: the field becomes first responder before its final on-screen position/frame
    /// settles, and a keyboard AutoFill invocation made against that not-yet-settled state
    /// silently fails (the very next AutoFill attempt, against the by-then-settled field, works).
    /// Deferring focus past the transition's duration avoids that race.
    static let identifierAutoFocusDelay: Duration = .seconds(pageTransitionSpringResponse)
    /// Tapping "Test connection" resigns the host field's focus in the same beat it starts the
    /// button's collapse-to-circle morph. The keyboard-dismiss animation and the morph then
    /// fight for the same frame, and the layout reflow from the keyboard closing swallows the
    /// spinner almost entirely. Letting the keyboard-dismiss animation finish first (this is
    /// UIKit's own keyboard animation duration) before starting the morph gives each its own
    /// beat, so the spinner is actually visible.
    static let keyboardDismissDuration: Duration = .seconds(0.25)
    /// Named coordinate space the submit button's rect is measured in, so the flood circle
    /// positions against the same origin regardless of scroll offset.
    static let rootSpace = "loginRoot"
    /// How long the collapsed submit button's accent circle takes to flood the screen.
    static let submitFloodDuration: Double = 0.34
    /// Scale that circle reaches — a `.size48` button circle blown up past the far corner of
    /// any phone from wherever the button sits.
    static let submitFloodScale: CGFloat = 34
}

public struct LoginFormView: View {
    private enum Field: Hashable {
        case host
        case identifier
        case password
    }

    @Bindable var store: StoreOf<LoginFormFeature>
    /// `false` while the launch splash still covers the screen — auto-focusing the host field
    /// then would slide the keyboard up over the splash.
    private let autoFocus: Bool
    /// Submit button's rect in this view's own space — the seed for the sign-in circle that
    /// floods the screen with accent (à la TKSubmitTransition, scaling the button itself).
    @State private var submitButtonRect: CGRect = .zero
    /// Scale of that flooding circle: 1 == exactly the collapsed button, grows to cover.
    @State private var submitFloodScale: CGFloat = 1
    @State private var shakeTrigger: CGFloat = 0
    @State private var identifierShakeTrigger: CGFloat = 0
    @State private var passwordShakeTrigger: CGFloat = 0
    /// Mirrors `store.errorMessage`, delayed on the way in and immediate on the way out.
    @State private var displayedErrorMessage: String?
    /// Red-borders the email/password fields for a couple seconds after a login failure; which
    /// field(s) light up follows `store.invalidFieldsScope`.
    @State private var isIdentifierFieldInvalid = false
    @State private var isPasswordFieldInvalid = false
    @FocusState private var focusedField: Field?
    /// Server-page scroll height, only to floor the centered content's `minHeight`. The
    /// credentials page deliberately has no such geometry read over its fields — an
    /// `.onGeometryChange` / `GeometryReader` ancestor is a documented AutoFill hazard.
    @State private var serverScrollHeight: CGFloat = 0

    public init(store: StoreOf<LoginFormFeature>, autoFocus: Bool = true) {
        self.store = store
        self.autoFocus = autoFocus
    }

    private var isSubmitLocalEnabled: Bool {
        !store.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.password.isEmpty
    }

    /// Resigns the host field and fires `testConnectionButtonTapped`. If a keyboard was up,
    /// waits out its dismiss animation first so it doesn't fight the button's collapse-to-circle
    /// morph for the same beat (see `Constants.keyboardDismissDuration`).
    private func submitTestConnection() {
        let wasKeyboardVisible = focusedField != nil
        focusedField = nil
        guard wasKeyboardVisible else {
            store.send(.testConnectionButtonTapped)
            return
        }
        Task {
            try? await Task.sleep(for: Constants.keyboardDismissDuration)
            guard !Task.isCancelled else { return }
            store.send(.testConnectionButtonTapped)
        }
    }

    /// Same beat-separation as `submitTestConnection`, for the credentials page: drop the
    /// keyboard first so its dismiss reflow doesn't shift the submit button mid collapse (and
    /// mid sign-in reveal), which reads as the circle starting off-center and stuttering.
    private func submitCredentials() {
        let wasKeyboardVisible = focusedField != nil
        focusedField = nil
        guard wasKeyboardVisible else {
            store.send(.continueButtonTapped)
            return
        }
        Task {
            try? await Task.sleep(for: Constants.keyboardDismissDuration)
            guard !Task.isCancelled else { return }
            store.send(.continueButtonTapped)
        }
    }

    private var hostPlaceholder: String {
        switch store.scheme {
        case .https: "nextexplorer.example.com"
        case .http: "192.168.1.50:3000"
        }
    }

    /// HTTP homelab servers are rarely on port 80. Nudge the user to include one
    /// rather than let the request silently go to the wrong port. Only shown once the
    /// user has stepped away from the field, so it doesn't flash on every keystroke
    /// before they've had a chance to type the port.
    private var missingPortWarning: String? {
        guard store.scheme == .http, focusedField != .host else { return nil }
        let trimmed = store.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hostOnly = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
        guard !hostOnly.contains(":") else { return nil }
        return L10n.Login.portHint
    }

    public var body: some View {
        ZStack {
            if store.currentPage == .server {
                serverPage
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                credentialsPage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(
            .spring(response: Constants.pageTransitionSpringResponse, dampingFraction: Constants.pageTransitionSpringDamping),
            value: store.currentPage
        )
        .backgroundGradient()
        .coordinateSpace(.named(Constants.rootSpace))
        .overlay {
            if store.submitPhase == .success, submitButtonRect != .zero {
                Circle()
                    .fill(Color.accent)
                    .frame(width: submitButtonRect.height, height: submitButtonRect.height)
                    .scaleEffect(submitFloodScale, anchor: .center)
                    // No `.ignoresSafeArea()`: `submitButtonRect` is measured in this view's
                    // safe-area-inset `loginRoot` space, so `.position` must resolve in that
                    // same space. Adding `.ignoresSafeArea()` here shifted the circle up by
                    // the top inset, so the flood started above the button. `.scaleEffect`
                    // alone blows it well past every screen edge.
                    .position(x: submitButtonRect.midX, y: submitButtonRect.midY)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: store.submitPhase) { _, phase in
            switch phase {
            case .success:
                submitFloodScale = 1
                withAnimation(.timingCurve(0.9, 0.0, 1, 0.1, duration: Constants.submitFloodDuration)) {
                    submitFloodScale = Constants.submitFloodScale
                }
            case .idle, .submitting, .failure:
                submitFloodScale = 1
            }
        }
        .modifier(LoginHapticsModifier(errorMessage: store.errorMessage, connectionPhase: store.connectionPhase))
        .onChange(of: store.errorMessage) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.default) {
                if store.currentPage == .server {
                    shakeTrigger += 1
                } else {
                    identifierShakeTrigger += 1
                    if store.invalidFieldsScope == .identifierAndPassword {
                        passwordShakeTrigger += 1
                    }
                }
            }
        }
        .task(id: store.errorMessage) {
            guard let message = store.errorMessage, !message.isEmpty else {
                withAnimation(.easeInOut(duration: Constants.errorFadeDuration)) {
                    displayedErrorMessage = nil
                    isIdentifierFieldInvalid = false
                    isPasswordFieldInvalid = false
                }
                return
            }
            try? await Task.sleep(for: Constants.errorRevealDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Constants.errorFadeDuration)) {
                displayedErrorMessage = message
            }

            guard store.currentPage == .credentials else { return }
            isIdentifierFieldInvalid = true
            isPasswordFieldInvalid = store.invalidFieldsScope == .identifierAndPassword
            try? await Task.sleep(for: Constants.invalidFieldsDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Constants.errorFadeDuration)) {
                isIdentifierFieldInvalid = false
                isPasswordFieldInvalid = false
            }
        }
    }

    // MARK: - Server page

    private var serverPage: some View {
        ScrollView {
            VStack(spacing: .space24) {
                Spacer(minLength: .space48)

                VStack(spacing: .zero) {
                    IconKit.logo
                        .resizable()
                        .frame(width: Constants.logoSize, height: Constants.logoSize)
                    Text(L10n.Login.serverQuestion)
                        .type(.headline3, style: .primary(for: .label))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, .space16)

                VStack(spacing: .space24) {
                    DSSegmentedControl(
                        options: LoginFormFeature.URLScheme.allCases,
                        selection: Binding(get: { store.scheme }, set: { store.send(.schemeChanged($0)) }),
                        label: \.displayName
                    )

                    // The picker also moves on its own: typing a leading digit (an IP) or an
                    // `http://` prefix flips it to http. See `LoginFormFeature.inferredScheme`.
                    TextField(
                        text: Binding(get: { store.host }, set: { store.send(.hostChanged($0)) }),
                        prompt: Text(hostPlaceholder).foregroundColor(Color.secondaryDS)
                    ) {
                        EmptyView()
                    }
                    .roundedFieldStyle(height: .size56)
                    .type(.body1(.regular))
                    .tint(Color.accent)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit(submitTestConnection)
                    .shake(trigger: shakeTrigger)
                    .focused($focusedField, equals: .host)
                    .onAppear { if autoFocus { focusedField = .host } }
                    .onChange(of: autoFocus) { _, ready in if ready { focusedField = .host } }
                }
                .padding(.horizontal, .space24)

                if let errorMessage = displayedErrorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .type(.body2(.semibold), style: .error)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .space24)
                        .transition(.opacity)
                } else if let warning = missingPortWarning {
                    Text(warning)
                        .type(.body1(.semibold), style: .warning)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .space24)
                        .transition(.opacity)
                }

                if !store.host.isEmpty {
                    testConnectionButton
                        .padding(.horizontal, .space24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer(minLength: .space48)
            }
            .frame(minHeight: serverScrollHeight)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { serverScrollHeight = $0 }
        // `.interactively` swallows the first tap on `testConnectionButton` while the
        // keyboard is up: that tap only starts the interactive dismiss gesture instead of
        // reaching the button, so the user has to tap twice. `.immediately` dismisses on
        // first touch instead, so the same tap reaches the button underneath.
        .scrollDismissesKeyboard(.immediately)
        .animation(.easeInOut(duration: Constants.quickFadeDuration), value: store.host.isEmpty)
        // Get the Local Network permission alert out of the way while the user is still
        // typing the address, not the moment they hit "Test connection".
        .onAppear { LocalNetworkPrimer.prime() }
    }

    private var testConnectionButton: some View {
        let isCollapsed = store.connectionPhase != .idle
        return DSAnimatedButton(
            phase: store.connectionPhase,
            isCollapsed: isCollapsed,
            style: {
                switch store.connectionPhase {
                case .idle, .testing: .inverted
                case .success: .success
                case .failure: .failure
                }
            }(),
            size: .medium,
            isHitEnabled: !isCollapsed,
            action: submitTestConnection
        ) {
            ZStack {
                switch store.connectionPhase {
                case .idle:
                    Text(L10n.Login.testConnection)
                        .type(.label3)
                        .foregroundStyle(.white)
                case .testing:
                    DSSpinner(color: .white)
                case .success:
                    IconKit.checkmark
                        .resizable()
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .foregroundStyle(.white)
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
    }

    // MARK: - Credentials page

    private var credentialsPage: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(store.host)
                    .type(.body1(.semibold), style: .primary(for: .label))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Constants.navBarTitleHorizontalPadding)

                HStack {
                    Button {
                        store.send(.backButtonTapped)
                    } label: {
                        IconKit.back
                            .resizable()
                            .frame(width: Constants.backChevronSize, height: Constants.backChevronSize)
                            .fontWeight(Constants.backChevronWeight)
                            .foregroundStyle(Color.primaryDS)
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    Spacer()
                }
            }
            .frame(height: Constants.navBarHeight)
            .padding(.horizontal, .space16)
            .padding(.top, .space16)

            ScrollView {
                VStack(alignment: .leading, spacing: .space24) {
                    identifierField
                    passwordField

                    // After the fields on purpose: a conditional sibling *above* them shifts
                    // their position in the container and drops the keyboard's AutoFill session.
                    if store.scheme == .http {
                        DSInfoCard(L10n.Login.plaintextWarning)
                    }

                    continueButton

                    if let errorMessage = displayedErrorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .type(.body2(.semibold), style: .error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, .space16)
                .padding(.top, .space32)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .backgroundGradient()
    }

    private var identifierField: some View {
        DSFieldContainer(label: L10n.Login.emailField, icon: IconKit.person, shakeTrigger: identifierShakeTrigger, isInvalid: isIdentifierFieldInvalid) {
            // Native `prompt:` rather than a ZStack placeholder overlay: a sibling view stacked
            // on the field is a documented AutoFill target-resolution hazard.
            TextField(
                text: Binding(get: { store.identifier }, set: { store.send(.identifierChanged($0)) }),
                prompt: Text("name@company.com").foregroundColor(Color.secondaryDS)
            ) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .type(.body1(.regular))
            .tint(Color.accent)
            .textContentType(.username)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focusedField, equals: .identifier)
            .task {
                try? await Task.sleep(for: Constants.identifierAutoFocusDelay)
                guard !Task.isCancelled else { return }
                focusedField = .identifier
            }
        }
    }

    private var passwordField: some View {
        DSFieldContainer(label: L10n.Login.passwordField, icon: IconKit.lock, shakeTrigger: passwordShakeTrigger, isInvalid: isPasswordFieldInvalid) {
            HStack(spacing: .space8) {
                // Both fields stay mounted at all times: swapping SecureField/TextField in and
                // out via `if/else` tears down and rebuilds the underlying text input on every
                // reveal toggle, which drops the AutoFill session iOS (and Bitwarden, 1Password,
                // etc.) had going for it. Toggling opacity/hit-testing instead keeps one stable
                // field identity so AutoFill keeps working across a visibility toggle.
                ZStack(alignment: .leading) {
                    SecureField(
                        text: Binding(get: { store.password }, set: { store.send(.passwordChanged($0)) }),
                        prompt: Text(Constants.maskedPasswordPlaceholder).foregroundColor(Color.secondaryDS)
                    ) {
                        EmptyView()
                    }
                    .opacity(store.isPasswordVisible ? 0 : 1)
                    .allowsHitTesting(!store.isPasswordVisible)
                    .accessibilityHidden(store.isPasswordVisible)
                    // Only the field currently on-screen may claim `.password`; both fields
                    // staying mounted with the same content type makes AutoFill's
                    // username/password pairing ambiguous and it silently declines to fill
                    // either (this is what broke Bitwarden autofill).
                    .textContentType(store.isPasswordVisible ? nil : .password)

                    TextField(
                        text: Binding(get: { store.password }, set: { store.send(.passwordChanged($0)) }),
                        prompt: Text(Constants.maskedPasswordPlaceholder).foregroundColor(Color.secondaryDS)
                    ) {
                        EmptyView()
                    }
                    .opacity(store.isPasswordVisible ? 1 : 0)
                    .allowsHitTesting(store.isPasswordVisible)
                    .accessibilityHidden(!store.isPasswordVisible)
                    .textContentType(store.isPasswordVisible ? .password : nil)
                }
                .textFieldStyle(.plain)
                .type(.body1(.regular))
                .tint(Color.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .password)

                if focusedField == .password {
                    Button {
                        store.send(.togglePasswordVisibility)
                    } label: {
                        (store.isPasswordVisible ? IconKit.eyeSlash : IconKit.eye)
                            .foregroundStyle(Color.secondaryDS)
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: Constants.contentFadeDuration), value: focusedField)
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
            action: submitCredentials
        ) {
            ZStack {
                switch phase {
                case .idle:
                    Text(L10n.Login.submit)
                        .type(.label3)
                        .foregroundStyle(Color.black)
                case .submitting:
                    DSSpinner(color: .black)
                case .success:
                    IconKit.checkmark
                        .resizable()
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .foregroundStyle(Color.black)
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
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Constants.rootSpace)) }) { newFrame in
            if newFrame != .zero { submitButtonRect = newFrame }
        }
        .animation(.easeInOut(duration: Constants.contentFadeDuration), value: isSubmitLocalEnabled)
    }
}

/// Split out of `LoginFormView.body` — inlining these three `.hapticFeedback` calls alongside
/// everything else already chained onto the root `ZStack` pushed the compiler's type-checker
/// past a reasonable time budget.
private struct LoginHapticsModifier: ViewModifier {
    let errorMessage: String?
    let connectionPhase: LoginFormFeature.ConnectionPhase

    func body(content: Content) -> some View {
        let withErrorFeedback = content.hapticFeedback(.error, trigger: errorMessage) { _, newValue in
            newValue != nil
        }
        return withErrorFeedback.modifier(ConnectionPhaseHapticsModifier(connectionPhase: connectionPhase))
    }
}

private struct ConnectionPhaseHapticsModifier: ViewModifier {
    let connectionPhase: LoginFormFeature.ConnectionPhase

    func body(content: Content) -> some View {
        content
            .hapticFeedback(.success, trigger: connectionPhase) { _, newValue in newValue == .success }
            .hapticFeedback(.error, trigger: connectionPhase) { _, newValue in newValue == .failure }
    }
}

#Preview("Server") {
    LoginFormView(
        store: Store(initialState: LoginFormFeature.State()) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
}

#Preview("Credentials") {
    LoginFormView(
        store: Store(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "nextexplorer.example.com",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: false)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
}
