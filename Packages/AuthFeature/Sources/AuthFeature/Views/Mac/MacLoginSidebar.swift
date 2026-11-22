#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let width: CGFloat = 360
        static let logoSize: CGFloat = .size64
        static let stepRowHeight: CGFloat = .size40
        static let stepBadgeSize: CGFloat = .size24
        static let checkSize: CGFloat = .iconXSmall
        static let topPadding: CGFloat = .size56
    }

    struct MacLoginSidebar: View {
        let store: StoreOf<LoginFormFeature>
        @State private var isServerInfoPresented = false

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                IconKit.logo
                    .resizable()
                    .frame(width: Constants.logoSize, height: Constants.logoSize)
                    .accessibilityHidden(true)
                Text(AppIdentity.name)
                    .accessibilityAddTraits(.isHeader)
                    .type(.display)
                    .foregroundStyle(Color.macChromeText)
                    .padding(.top, .space24)
                VStack(alignment: .leading, spacing: .space4) {
                    ForEach(MacLoginStep.visible(on: store.currentPage), id: \.self) { step in
                        MacLoginStepRow(step: step, state: step.state(current: MacLoginStep(page: store.currentPage)))
                    }
                }
                .padding(.top, .space32)
                Spacer(minLength: .space24)
                VStack(alignment: .leading, spacing: .space2) {
                    MacLoginFooterLink(title: L10n.Login.serverInfoTitle, icon: IconKit.info) {
                        isServerInfoPresented = true
                    }
                    .accessibilityHint(L10n.Login.serverInfoAccessibility)
                    MacLoginFooterLink(title: certificateTitle, icon: IconKit.lock) {
                        store.send(.changeClientCertificateTapped)
                    }
                    .disabled(!canManageCertificate)
                    LoginDiagnosticsButton(diagnostics: store.diagnostics)
                }
            }
            .padding(.horizontal, .space32)
            .padding(.top, Constants.topPadding)
            .padding(.bottom, .space24)
            .frame(width: Constants.width, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .dsSheet(isPresented: $isServerInfoPresented) {
                ServerInfoSheet(onClose: { isServerInfoPresented = false })
            }
        }

        private var certificateTitle: String {
            store.certificateInUse == nil ? L10n.Login.addClientCertificate : L10n.Login.manageClientCertificate
        }

        private var canManageCertificate: Bool {
            LoginFormFeature.normalizedURL(scheme: store.scheme, host: store.host) != nil
        }
    }

    private struct MacLoginStepRow: View {
        let step: MacLoginStep
        let state: MacLoginStepState

        var body: some View {
            HStack(spacing: .space12) {
                badge
                Text(step.title)
                    .type(.body2(state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .upcoming ? Color.macChromeSecondary : Color.macChromeText)
                Spacer(minLength: .zero)
            }
            .padding(.horizontal, .space12)
            .frame(height: Constants.stepRowHeight)
            .background {
                if state == .current {
                    RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                        .fill(Color.macSelection)
                        .elevation(.level1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(state == .current ? .isSelected : [])
        }

        private var badge: some View {
            ZStack {
                Circle().fill(state == .current ? Color.accent : Color.macChromeButton)
                switch state {
                case .done:
                    IconKit.checkmark
                        .resizable()
                        .scaledToFit()
                        .bold()
                        .frame(width: Constants.checkSize, height: Constants.checkSize)
                        .foregroundStyle(Color.accentText)
                case .current, .upcoming:
                    Text(step.rawValue.formatted())
                        .type(.caption(.bold))
                        .foregroundStyle(state == .current ? Color.onAccent : Color.macChromeSecondary)
                }
            }
            .frame(width: Constants.stepBadgeSize, height: Constants.stepBadgeSize)
        }
    }

    struct MacLoginFooterLink: View {
        let title: String
        let icon: Image
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Label {
                    Text(title).type(.body2(.regular))
                } icon: {
                    icon
                }
                .foregroundStyle(Color.macChromeText)
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: Constants.stepRowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                        .fill(isHovered ? Color.macChromeHover : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(DSMotion.quickFade, value: isHovered)
        }
    }

    #Preview("Server step") {
        MacLoginSidebar(store: Store(initialState: LoginFormFeature.State()) { LoginFormFeature() })
            .frame(height: 640)
            .macChromeBackground()
    }

    #Preview("Code step, dark") {
        MacLoginSidebar(
            store: Store(initialState: LoginFormFeature.State(
                currentPage: .secondFactor,
                host: "nextexplorer.example.com"
            )) {
                LoginFormFeature()
            }
        )
        .frame(height: 640)
        .macChromeBackground()
        .environment(\.colorScheme, .dark)
    }
#endif
