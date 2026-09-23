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
    static let ssoIconSize: CGFloat = .iconSmall
    /// How long after a failed Test Connection (once the button has morphed into the red X
    /// and the field has shaken) the error text waits before fading in.
    static let errorRevealDelay: Duration = .seconds(0.4)
    static let errorFadeDuration: Double = 0.3
    /// How long the email/password fields stay red-bordered after a login failure.
    static let invalidFieldsDuration: Duration = .seconds(2)
    static let logoSize: CGFloat = .size96
    static let credentialsLogoSize: CGFloat = .size56
    /// On regular width (iPad, not compact multitasking) the login form floats in a centered
    /// surface card over the full-bleed gradient, rather than stretching edge to edge.
    static let cardWidth: CGFloat = 440
    static let cardMaxHeight: CGFloat = 620
    static let cardOuterPadding: CGFloat = .space24
    /// Login card background gradient stops (regular width). Top leading #FFC228 into bottom
    /// trailing #FF9D00, a warm amber accent wash.
    static let backgroundGradientTop = Color(red: 1.0, green: 194.0 / 255.0, blue: 40.0 / 255.0)
    static let backgroundGradientBottom = Color(red: 1.0, green: 157.0 / 255.0, blue: 0.0)
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
    static let macButtonHiddenScale: CGFloat = 0.9
    static let macButtonPopDuration: Double = 0.3
    static let macButtonPopBounce: Double = 0.35
    /// Named coordinate space the submit button's rect is measured in, so the flood circle
    /// positions against the same origin regardless of scroll offset.
    static let rootSpace = "loginRoot"
    /// How long the collapsed submit button's accent circle takes to flood the screen.
    static let submitFloodDuration: Double = 0.34
    /// Scale that circle reaches — a `.size48` button circle blown up past the far corner of
    /// any phone from wherever the button sits.
    static let submitFloodScale: CGFloat = 34
    static let dividerOpacity: Double = 0.35
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
    /// SSO button's rect + its own flood circle scale, so an SSO sign-in floods from the SSO
    /// button the same way a password one floods from the submit button.
    @State private var ssoButtonRect: CGRect = .zero
    @State private var ssoFloodScale: CGFloat = 1
    /// When Reduce Motion is on, the full-screen accent flood (a large scaling animation) is
    /// suppressed; `AppView` already hands sign-in an instant, motion-free reveal instead.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Regular width gets the centered login card; compact (iPhone, iPad narrow multitasking)
    /// stays full bleed. Gated on size class, never device idiom, so Split View / Slide Over
    /// fall back to the phone layout.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    /// Drives the "What is a server?" info sheet from the `(i)` beside the server-page title.
    @State private var isServerInfoPresented = false

    public init(store: StoreOf<LoginFormFeature>, autoFocus: Bool = true) {
        self.store = store
        self.autoFocus = autoFocus
    }

    /// A Mac has no on screen keyboard, so there is no dismiss animation to wait out before submitting.
    private static var hasSoftwareKeyboard: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    private var isSubmitLocalEnabled: Bool {
        !store.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.password.isEmpty
    }

    /// Resigns the host field and fires `testConnectionButtonTapped`. If a keyboard was up,
    /// waits out its dismiss animation first so it doesn't fight the button's collapse-to-circle
    /// morph for the same beat (see `Constants.keyboardDismissDuration`).
    private func submitTestConnection() {
        let wasKeyboardVisible = Self.hasSoftwareKeyboard && focusedField != nil
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
        let wasKeyboardVisible = Self.hasSoftwareKeyboard && focusedField != nil
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

    /// Same beat-separation for SSO: drop the keyboard and let its dismiss animation finish
    /// before `.ssoButtonTapped` presents the web sheet, otherwise the keyboard stays up
    /// underneath (and behind) the ASWebAuthenticationSession sheet.
    private func submitSSO() {
        let wasKeyboardVisible = Self.hasSoftwareKeyboard && focusedField != nil
        focusedField = nil
        guard wasKeyboardVisible else {
            store.send(.ssoButtonTapped)
            return
        }
        Task {
            try? await Task.sleep(for: Constants.keyboardDismissDuration)
            guard !Task.isCancelled else { return }
            store.send(.ssoButtonTapped)
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
            cardWrappedPages
        }
        .background(loginBackground)
        .coordinateSpace(.named(Constants.rootSpace))
        .overlay {
            if !reduceMotion, store.submitPhase == .success, submitButtonRect != .zero {
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
            if !reduceMotion, store.oidcPhase == .success, ssoButtonRect != .zero {
                // Same TKSubmitTransition flood, seeded from the SSO button so an SSO sign-in
                // grows into the app exactly like a password one, rather than snapping in.
                Circle()
                    .fill(Color.accent)
                    .frame(width: ssoButtonRect.height, height: ssoButtonRect.height)
                    .scaleEffect(ssoFloodScale, anchor: .center)
                    .position(x: ssoButtonRect.midX, y: ssoButtonRect.midY)
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
        .onChange(of: store.oidcPhase) { _, phase in
            switch phase {
            case .success:
                ssoFloodScale = 1
                withAnimation(.timingCurve(0.9, 0.0, 1, 0.1, duration: Constants.submitFloodDuration)) {
                    ssoFloodScale = Constants.submitFloodScale
                }
            case .idle, .authenticating:
                ssoFloodScale = 1
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

    /// Screen background. Regular width (the card layout) sits on a warm amber accent wash so
    /// the white card floats on a brand gradient; compact keeps the neutral app gradient.
    private var loginBackground: some View {
        Group {
            if horizontalSizeClass == .regular {
                LinearGradient(
                    colors: [Constants.backgroundGradientTop, Constants.backgroundGradientBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient.backgroundPrimary
            }
        }
        .ignoresSafeArea()
    }

    /// The two sliding pages. On regular width they float in a centered surface card over the
    /// gradient; on compact they stay full bleed exactly as before.
    @ViewBuilder
    private var cardWrappedPages: some View {
        if horizontalSizeClass == .regular {
            // Wrap the floating card in a keyboard-aware ScrollView: with the fields inside the
            // page's own scroll view, SwiftUI's keyboard avoidance only shifts that inner scroll,
            // so a fixed-height centered card keeps its lower half (the field + button) behind the
            // keyboard in iPad landscape. This outer scroll can lift the whole card instead;
            // `containerRelativeFrame` keeps it centered when there's room to spare.
            ScrollView {
                styledCard
                    .containerRelativeFrame(.vertical, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        } else {
            pages
        }
    }

    private var styledCard: some View {
        pages
            .frame(maxWidth: Constants.cardWidth, maxHeight: Constants.cardMaxHeight)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
            .elevation(.level16)
            .frame(maxWidth: .infinity)
            .padding(Constants.cardOuterPadding)
    }

    private var pages: some View {
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
                    Button {
                        isServerInfoPresented = true
                    } label: {
                        // Inline `(i)` flowing right after the title text (`Text` image, so it
                        // scales with the type and wraps with the sentence), the whole title
                        // acting as the tap target.
                        (
                            Text(L10n.Login.serverQuestion)
                                + Text(" ")
                                + Text(IconKit.info)
                                .font(Typography.TextType.body2(.regular).font())
                                .foregroundColor(Color.secondaryDS)
                        )
                        .type(.headline3, style: .primaryOnSurface)
                        .multilineTextAlignment(.center)
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .accessibilityLabel(L10n.Login.serverQuestion)
                    .accessibilityHint(L10n.Login.serverInfoAccessibility)
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
                    .accessibilityIdentifier(AccessibilityIdentifiers.Login.hostField)
                    .focused($focusedField, equals: .host)
                    .onAppear {
                        if autoFocus {
                            focusedField = .host
                        }
                    }
                    .onChange(of: autoFocus) {
                        _, ready in if ready {
                            focusedField = .host
                        }
                    }
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

                #if os(macOS)
                    // No keyboard reflow on a Mac: the slot is always reserved, so the button
                    // pops in place without shifting anything around it.
                    testConnectionButton
                        .padding(.horizontal, .space24)
                        .opacity(store.host.isEmpty ? 0 : 1)
                        .scaleEffect(store.host.isEmpty ? Constants.macButtonHiddenScale : 1)
                        .allowsHitTesting(!store.host.isEmpty)
                        .accessibilityHidden(store.host.isEmpty)
                        .animation(.spring(duration: Constants.macButtonPopDuration, bounce: Constants.macButtonPopBounce), value: store.host.isEmpty)
                #else
                    if !store.host.isEmpty {
                        testConnectionButton
                            .padding(.horizontal, .space24)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                #endif

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
        .sheet(isPresented: $isServerInfoPresented) {
            ServerInfoSheet(onClose: { isServerInfoPresented = false })
        }
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
            testConnectionButtonLabel
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.Login.testConnectionButton)
    }

    @ViewBuilder
    private var testConnectionButtonLabel: some View {
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

    // MARK: - Credentials page

    private var credentialsPage: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(store.host)
                    .type(.body1(.semibold), style: .primaryOnSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Constants.navBarTitleHorizontalPadding)

                HStack {
                    Button {
                        store.send(.backButtonTapped)
                    } label: {
                        // Sized via font, not `.resizable()` into a square frame: a chevron is
                        // not square, so a square resizable frame stretches the glyph. The 44pt
                        // frame is the tap target.
                        IconKit.back
                            .font(.system(size: Constants.backChevronSize, weight: Constants.backChevronWeight))
                            .foregroundStyle(Color.primaryDS)
                            .frame(width: .size44, height: .size44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .accessibilityLabel(L10n.Common.back)
                    Spacer()
                }
            }
            .frame(height: Constants.navBarHeight)
            .padding(.horizontal, .space16)
            .padding(.top, .space16)

            ScrollView {
                VStack(alignment: .leading, spacing: .space24) {
                    if store.authStatus?.localEnabled == true {
                        identifierField
                        passwordField

                        // After the fields on purpose: a conditional sibling *above* them shifts
                        // their position in the container and drops the keyboard's AutoFill session.
                        if store.scheme == .http {
                            DSInfoCard(L10n.Login.plaintextWarning)
                        }

                        continueButton
                    }

                    if store.authStatus?.oidcEnabled == true {
                        if store.authStatus?.localEnabled == true {
                            orDivider
                        }
                        ssoButton
                    }

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
        // Opaque so the outgoing page can't show through mid slide. In the card (regular width)
        // that fill is the card surface; full bleed it stays the gradient.
        .background {
            if horizontalSizeClass == .regular {
                Color.backgroundSecondary
            } else {
                LinearGradient.backgroundPrimary.ignoresSafeArea()
            }
        }
    }

    private var identifierField: some View {
        DSFieldContainer(label: L10n.Login.emailField, icon: IconKit.person, shakeTrigger: identifierShakeTrigger, isInvalid: isIdentifierFieldInvalid) {
            // Native `prompt:` rather than a ZStack placeholder overlay: a sibling view stacked
            // on the field is a documented AutoFill target-resolution hazard.
            TextField(
                text: Binding(get: { store.identifier }, set: { store.send(.identifierChanged($0)) }),
                // `verbatim` so the email-shaped placeholder isn't markdown/link inferred (iOS 18
                // renders an inferred email as a blue link, ignoring the prompt's own color).
                prompt: Text(verbatim: "name@company.com").foregroundStyle(Color.secondaryDS)
            ) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .type(.body1(.regular))
            .tint(Color.accent)
            .textContentType(.username)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier(AccessibilityIdentifiers.Login.emailField)
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
                    .accessibilityIdentifier(AccessibilityIdentifiers.Login.passwordField)
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
                    .accessibilityIdentifier(AccessibilityIdentifiers.Login.passwordFieldVisible)
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
                            .frame(minWidth: .size44, minHeight: .size44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .accessibilityLabel(store.isPasswordVisible ? L10n.Login.hidePassword : L10n.Login.showPassword)
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
        .accessibilityIdentifier(AccessibilityIdentifiers.Login.submitButton)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Constants.rootSpace)) }) { newFrame in
            if newFrame != .zero {
                submitButtonRect = newFrame
            }
        }
        .animation(.easeInOut(duration: Constants.contentFadeDuration), value: isSubmitLocalEnabled)
    }

    private var orDivider: some View {
        HStack(spacing: .space12) {
            Rectangle().fill(Color.secondaryDS.opacity(Constants.dividerOpacity)).frame(height: 1)
            Text(L10n.Login.orDivider)
                .type(.body2(.semibold), style: .secondary)
                .fixedSize()
            Rectangle().fill(Color.secondaryDS.opacity(Constants.dividerOpacity)).frame(height: 1)
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
            style: phase == .success ? .primary : .outline,
            size: .medium,
            isHitEnabled: !isCollapsed,
            action: submitSSO
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
                    .foregroundStyle(Color.primaryDS)
                case .authenticating:
                    DSSpinner(color: .primaryDS)
                case .success:
                    IconKit.checkmark
                        .resizable()
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .foregroundStyle(Color.black)
                        .bold()
                }
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Constants.rootSpace)) }) { newFrame in
            if newFrame != .zero {
                ssoButtonRect = newFrame
            }
        }
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

#Preview("Credentials Local + SSO") {
    LoginFormView(
        store: Store(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "nextexplorer.example.com",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: true)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
}

#Preview("Credentials SSO only") {
    LoginFormView(
        store: Store(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "sso.example.com",
                authStatus: AuthStatus(localEnabled: false, oidcEnabled: true)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
}

#Preview("Card · Server (regular)") {
    LoginFormView(
        store: Store(initialState: LoginFormFeature.State()) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
    .environment(\.horizontalSizeClass, .regular)
}

#Preview("Card · Credentials (regular)") {
    LoginFormView(
        store: Store(
            initialState: LoginFormFeature.State(
                currentPage: .credentials,
                connectionPhase: .success,
                host: "nextexplorer.example.com",
                authStatus: AuthStatus(localEnabled: true, oidcEnabled: true)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
    .environment(\.horizontalSizeClass, .regular)
}
