import AuthClient
import ComposableArchitecture
import CoreModels
import DesignSystem
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
}

public struct LoginFormView: View {
    private enum Field: Hashable {
        case host
        case identifier
        case password
    }

    @Bindable var store: StoreOf<LoginFormFeature>
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
    /// Scroll container height, used only to give the centered content a `minHeight` floor,
    /// read via `.onGeometryChange` rather than wrapping the fields in a `GeometryReader`.
    /// A `GeometryReader` ancestor over `identifierField`/`passwordField` is the prime suspect
    /// for third-party Password AutoFill (Bitwarden) silently filling neither field: it delays
    /// giving its subtree a concrete size until layout settles, which can leave AutoFill unable
    /// to resolve a usable target rect for text insertion. Unverified on-device (no UI
    /// automation access in this environment); re-test AutoFill after this change.
    @State private var serverScrollHeight: CGFloat = 0
    @State private var credentialsScrollHeight: CGFloat = 0

    public init(store: StoreOf<LoginFormFeature>) {
        self.store = store
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
        return "Add a port (e.g. :3000). Most homelab servers don't listen on plain port 80."
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
                    Text("Where's your instance of NextExplorer?")
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
                    .onAppear { focusedField = .host }
                }
                .padding(.horizontal, .space24)

                if let errorMessage = displayedErrorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .type(.body1(.semibold), style: .error)
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
                    Text("Test connection")
                        .type(.label3)
                        .foregroundStyle(.white)
                case .testing:
                    ProgressView().tint(.white)
                case .success:
                    IconKit.checkmark
                        .resizable()
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .foregroundStyle(.white)
                        .bold()
                case .failure:
                    IconKit.xmark
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
                        IconKit.chevronLeft
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
                VStack(spacing: .space24) {
                    Spacer(minLength: .space48)
                    VStack(alignment: .leading, spacing: .space24) {
                        identifierField
                        passwordField
                        continueButton

                        if let errorMessage = displayedErrorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .type(.body2(.semibold), style: .error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, .space16)

                    Spacer(minLength: .space48)
                }
                .frame(minHeight: credentialsScrollHeight)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { credentialsScrollHeight = $0 }
            .scrollDismissesKeyboard(.immediately)
        }
        .backgroundGradient()
    }

    private var identifierField: some View {
        DSFieldContainer(label: "Email", icon: IconKit.person, shakeTrigger: identifierShakeTrigger, isInvalid: isIdentifierFieldInvalid) {
            ZStack(alignment: .leading) {
                if store.identifier.isEmpty {
                    DSPlaceholderText("name@company.com")
                }

                TextField(text: Binding(get: { store.identifier }, set: { store.send(.identifierChanged($0)) })) {
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
    }

    private var passwordField: some View {
        DSFieldContainer(label: "Password", icon: IconKit.lock, shakeTrigger: passwordShakeTrigger, isInvalid: isPasswordFieldInvalid) {
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
        DSButton(
            "Log In",
            style: .primary,
            size: .medium,
            isLoading: store.isSubmitting
        ) {
            store.send(.continueButtonTapped)
        }
        .disabled(!isSubmitLocalEnabled && !store.isSubmitting)
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
