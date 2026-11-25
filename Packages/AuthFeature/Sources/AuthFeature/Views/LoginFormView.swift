import AuthClient
import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    /// How long after a failed Test Connection (once the button has morphed into the red X
    /// and the field has shaken) the error text waits before fading in.
    static let errorRevealDelay: Duration = .seconds(0.4)
    /// How long the email and password fields stay red bordered after a login failure.
    static let invalidFieldsDuration: Duration = .seconds(2)
    /// Named coordinate space the submit button's rect is measured in, so the flood circle
    /// positions against the same origin regardless of scroll offset.
    static let rootSpace = LoginCoordinateSpace.root
    /// How long the collapsed submit button's accent circle takes to flood the screen.
    static let submitFloodDuration: Double = 0.34
    /// Scale that circle reaches: a `.size48` button circle blown up past the far corner of
    /// any phone from wherever the button sits.
    static let submitFloodScale: CGFloat = 34
}

/// The named space the sign in flood is positioned in, shared so each page's submit button can
/// report its rect in the space the overlay draws in.
enum LoginCoordinateSpace {
    static let root = "loginRoot"
}

public struct LoginFormView: View {
    @Bindable var store: StoreOf<LoginFormFeature>
    /// `false` while the launch splash still covers the screen: auto focusing the host field
    /// then would slide the keyboard up over the splash.
    private let shouldAutoFocus: Bool
    /// Whether a successful sign in floods the screen with accent into the app. Off where the
    /// form is a dialog (the Mac Add Account sheet), which simply closes instead.
    private let shouldFloodIntoApp: Bool
    private let hasStepsSidebar: Bool
    /// Submit button's rect in this view's own space: the seed for the sign in circle that
    /// floods the screen with accent, scaling the button itself.
    @State private var submitButtonRect: CGRect = .zero
    /// Scale of that flooding circle: 1 == exactly the collapsed button, grows to cover.
    @State private var submitFloodScale: CGFloat = 1
    /// SSO button's rect + its own flood circle scale, so an SSO sign in floods from the SSO
    /// button the same way a password one floods from the submit button.
    @State private var ssoButtonRect: CGRect = .zero
    @State private var ssoFloodScale: CGFloat = 1
    /// When Reduce Motion is on, the full screen accent flood (a large scaling animation) is
    /// suppressed; `AppView` already hands sign in an instant, motion free reveal instead.
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
    /// Red borders the email/password fields for a couple seconds after a login failure; which
    /// field(s) light up follows `store.invalidFieldsScope`.
    @State private var isIdentifierFieldInvalid = false
    @State private var isPasswordFieldInvalid = false

    public init(
        store: StoreOf<LoginFormFeature>,
        shouldAutoFocus: Bool = true,
        shouldFloodIntoApp: Bool = true,
        hasStepsSidebar: Bool = true
    ) {
        self.store = store
        self.shouldAutoFocus = shouldAutoFocus
        self.shouldFloodIntoApp = shouldFloodIntoApp
        self.hasStepsSidebar = hasStepsSidebar
    }

    public var body: some View {
        ZStack {
            #if os(macOS)
                MacLoginLayout(store: store, hasStepsSidebar: hasStepsSidebar) { pages }
            #else
                cardWrappedPages
                    .background(loginBackground)
            #endif
        }
        .coordinateSpace(.named(Constants.rootSpace))
        .overlay {
            if shouldFloodIntoApp, !reduceMotion, store.submitPhase == .success, submitButtonRect != .zero {
                Circle()
                    .fill(Color.accent)
                    .frame(width: submitButtonRect.height, height: submitButtonRect.height)
                    .scaleEffect(submitFloodScale, anchor: .center)
                    // No `.ignoresSafeArea()`: `submitButtonRect` is measured in this view's
                    // safe area inset `loginRoot` space, so `.position` must resolve in that
                    // same space. Adding `.ignoresSafeArea()` here shifted the circle up by
                    // the top inset, so the flood started above the button. `.scaleEffect`
                    // alone blows it well past every screen edge.
                    .position(x: submitButtonRect.midX, y: submitButtonRect.midY)
                    .allowsHitTesting(false)
            }
            if shouldFloodIntoApp, !reduceMotion, store.oidcPhase == .success, ssoButtonRect != .zero {
                // The same flood, seeded from the SSO button so an SSO sign in grows into the
                // app exactly like a password one, rather than snapping in.
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
        .dsSheet(item: $store.scope(state: \.clientCertificate, action: \.clientCertificate)) { certificateStore in
            ClientCertificateSheet(store: certificateStore)
        }
        .onChange(of: store.errorMessage) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(DSMotion.stateFade) {
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
                withAnimation(DSMotion.contentReveal) {
                    displayedErrorMessage = nil
                    isIdentifierFieldInvalid = false
                    isPasswordFieldInvalid = false
                }
                return
            }
            try? await DSMotion.waitForStep(Constants.errorRevealDelay)
            guard !Task.isCancelled else { return }
            withAnimation(DSMotion.contentReveal) {
                displayedErrorMessage = message
            }

            guard store.currentPage == .credentials else { return }
            isIdentifierFieldInvalid = true
            isPasswordFieldInvalid = store.invalidFieldsScope == .identifierAndPassword
            try? await Task.sleep(for: Constants.invalidFieldsDuration)
            guard !Task.isCancelled else { return }
            withAnimation(DSMotion.contentReveal) {
                isIdentifierFieldInvalid = false
                isPasswordFieldInvalid = false
            }
        }
    }

    #if os(iOS)
        /// Screen background. Regular width (the card layout) sits on a warm amber accent wash so
        /// the white card floats on a brand gradient; compact keeps the neutral app gradient.
        private var loginBackground: some View {
            Group {
                if horizontalSizeClass == .regular {
                    LoginCardBackground()
                } else {
                    LinearGradient.backgroundPrimary.ignoresSafeArea()
                }
            }
        }

        /// The two sliding pages. On regular width they float in a centered surface card over the
        /// gradient; on compact they stay full bleed exactly as before.
        @ViewBuilder
        private var cardWrappedPages: some View {
            if horizontalSizeClass == .regular {
                // Wrap the floating card in a keyboard aware ScrollView: with the fields inside the
                // page's own scroll view, SwiftUI's keyboard avoidance only shifts that inner scroll,
                // so a fixed height centered card keeps its lower half (the field + button) behind the
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
                .loginCard()
        }
    #endif

    private var pages: some View {
        ZStack {
            if store.currentPage == .server {
                LoginServerPage(
                    store: store,
                    shouldAutoFocus: shouldAutoFocus,
                    horizontalSizeClass: horizontalSizeClass,
                    shakeTrigger: shakeTrigger,
                    displayedErrorMessage: displayedErrorMessage
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else if store.currentPage == .credentials {
                LoginCredentialsPage(
                    store: store,
                    horizontalSizeClass: horizontalSizeClass,
                    identifierShakeTrigger: identifierShakeTrigger,
                    passwordShakeTrigger: passwordShakeTrigger,
                    isIdentifierFieldInvalid: isIdentifierFieldInvalid,
                    isPasswordFieldInvalid: isPasswordFieldInvalid,
                    displayedErrorMessage: displayedErrorMessage,
                    submitButtonRect: $submitButtonRect,
                    ssoButtonRect: $ssoButtonRect
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                LoginSecondFactorPage(
                    store: store,
                    horizontalSizeClass: horizontalSizeClass,
                    submitButtonRect: $submitButtonRect
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .animation(
            DSMotion.pageTransition,
            value: store.currentPage
        )
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
