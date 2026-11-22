import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let logoSize: CGFloat = .size96
    static let checkmarkSize: CGFloat = .iconSmall
    static let macButtonHiddenScale: CGFloat = 0.9
    #if os(macOS)
        static var idleButtonStyle: DSButtonStyle {
            .primary
        }

        static let idleLabelColor: Color = .onAccent
    #else
        static var idleButtonStyle: DSButtonStyle {
            .inverted
        }

        static let idleLabelColor: Color = .white
    #endif
}

/// The sign in form's first page: the server's address, its scheme, a client certificate when
/// the server asks for one, and Test connection.
struct LoginServerPage: View {
    @Bindable var store: StoreOf<LoginFormFeature>
    /// `false` while the launch splash still covers the screen: focusing the host field then
    /// would slide the keyboard up over the splash.
    let shouldAutoFocus: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let shakeTrigger: CGFloat
    let displayedErrorMessage: String?

    @FocusState private var isHostFocused: Bool
    /// Only floors the centered content's `minHeight`.
    @State private var serverScrollHeight: CGFloat = 0
    #if os(iOS)
        /// The "What is a server?" sheet behind the `(i)` beside the title.
        @State private var isServerInfoPresented = false
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: .space24) {
                Spacer(minLength: .space48)

                header

                VStack(spacing: .space24) {
                    DSSegmentedControl(
                        options: LoginFormFeature.URLScheme.allCases,
                        selection: Binding(get: { store.scheme }, set: { store.send(.schemeChanged($0)) }),
                        shouldAlwaysUsePill: true,
                        label: \.displayName
                    )

                    // The picker also moves on its own: typing a leading digit (an IP) or an
                    // `http://` prefix flips it to http. See `LoginFormFeature.inferredScheme`.
                    TextField(
                        text: Binding(get: { store.host }, set: { store.send(.hostChanged($0)) }),
                        prompt: Text(hostPlaceholder).foregroundColor(Color.secondaryText)
                    ) {
                        EmptyView()
                    }
                    #if os(macOS)
                    .macLargeField(isFocused: isHostFocused)
                    #else
                    .roundedFieldStyle(height: .size56)
                    #endif
                    .type(.body1(.regular))
                    .tint(Color.accent)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit(submitTestConnection)
                    .shake(trigger: shakeTrigger)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Login.hostField)
                    .focused($isHostFocused)
                    .onAppear {
                        if shouldAutoFocus {
                            isHostFocused = true
                        }
                    }
                    .onChange(of: shouldAutoFocus) {
                        _, ready in if ready {
                            isHostFocused = true
                        }
                    }
                }
                .padding(.horizontal, .space24)

                message

                if let prompt = store.certificatePrompt {
                    LoginCertificateButton(isRejected: prompt.isRejected) {
                        isHostFocused = false
                        store.send(.clientCertificateButtonTapped)
                    }
                    .padding(.horizontal, .space24)
                    .transition(.opacity)
                } else if let summary = store.certificateInUse {
                    LoginCertificateStatus(summary: summary) {
                        isHostFocused = false
                        store.send(.changeClientCertificateTapped)
                    }
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
                        .animation(
                            DSMotion.pop,
                            value: store.host.isEmpty
                        )
                #else
                    if !store.host.isEmpty {
                        testConnectionButton
                            .padding(.horizontal, .space24)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                #endif

                #if os(iOS)
                    LoginDiagnosticsButton(diagnostics: store.diagnostics)
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
        .background { LoginPageSurface(horizontalSizeClass: horizontalSizeClass) }
        .animation(DSMotion.stateFade, value: store.host.isEmpty)
        // Get the Local Network permission alert out of the way while the user is still
        // typing the address, not the moment they hit "Test connection".
        .onAppear { LocalNetworkPrimer.prime() }
        #if os(iOS)
            .dsSheet(isPresented: $isServerInfoPresented) {
                ServerInfoSheet(onClose: { isServerInfoPresented = false })
            }
        #endif
    }

    private var header: some View {
        #if os(macOS)
            Text(L10n.Login.serverQuestion)
                .type(.headline1)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .space24)
        #else
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
                            .foregroundColor(Color.secondaryText)
                    )
                    .type(.headline3, style: .primaryOnSurface)
                    .multilineTextAlignment(.center)
                }
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityLabel(L10n.Login.serverQuestion)
                .accessibilityHint(L10n.Login.serverInfoAccessibility)
            }
            .padding(.horizontal, .space16)
        #endif
    }

    @ViewBuilder
    private var message: some View {
        #if os(macOS)
            if let errorMessage = displayedErrorMessage, !errorMessage.isEmpty {
                MacNote(errorMessage, kind: .error)
                    .padding(.horizontal, .space24)
                    .transition(.opacity)
            } else if let warning = missingPortWarning {
                MacNote(warning, kind: .info)
                    .padding(.horizontal, .space24)
                    .transition(.opacity)
            }
        #else
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
        #endif
    }

    private var testConnectionButton: some View {
        let isCollapsed = store.connectionPhase != .idle
        return DSAnimatedButton(
            phase: store.connectionPhase,
            isCollapsed: isCollapsed,
            style: {
                switch store.connectionPhase {
                case .idle, .testing: Constants.idleButtonStyle
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

    private var testConnectionButtonLabel: some View {
        ZStack {
            switch store.connectionPhase {
            case .idle:
                Text(L10n.Login.testConnection)
                    .type(.label3)
                    .foregroundStyle(Constants.idleLabelColor)
            case .testing:
                DSSpinner(color: Constants.idleLabelColor)
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

    private var hostPlaceholder: String {
        switch store.scheme {
        case .https: "nextexplorer.example.com"
        case .http: "192.168.1.50:3000"
        }
    }

    /// HTTP homelab servers are rarely on port 80, so nudge the user to include one. Shown only
    /// once they have left the field, so it doesn't flash on every keystroke before the port.
    private var missingPortWarning: String? {
        guard store.scheme == .http, !isHostFocused else { return nil }
        let trimmed = store.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hostOnly = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
        guard !hostOnly.contains(":") else { return nil }
        return L10n.Login.portHint
    }

    private func submitTestConnection() {
        let wasFocused = isHostFocused
        isHostFocused = false
        LoginKeyboard.send(.testConnectionButtonTapped, to: store, afterDismissing: wasFocused)
    }
}

#Preview("Empty") {
    LoginServerPage(
        store: Store(initialState: LoginFormFeature.State()) { LoginFormFeature() },
        shouldAutoFocus: false,
        horizontalSizeClass: .compact,
        shakeTrigger: 0,
        displayedErrorMessage: nil
    )
}

#Preview("Address, http") {
    LoginServerPage(
        store: Store(initialState: LoginFormFeature.State(scheme: .http, host: "192.168.1.50")) {
            LoginFormFeature()
        },
        shouldAutoFocus: false,
        horizontalSizeClass: .compact,
        shakeTrigger: 0,
        displayedErrorMessage: nil
    )
}

#Preview("Error") {
    LoginServerPage(
        store: Store(initialState: LoginFormFeature.State(
            connectionPhase: .failure,
            host: "nextexplorer.example.com"
        )) {
            LoginFormFeature()
        },
        shouldAutoFocus: false,
        horizontalSizeClass: .compact,
        shakeTrigger: 0,
        displayedErrorMessage: L10n.Login.portHint
    )
}
