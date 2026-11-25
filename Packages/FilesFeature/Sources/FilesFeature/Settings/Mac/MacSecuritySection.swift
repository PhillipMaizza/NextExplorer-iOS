#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacSecuritySection: View {
        let store: StoreOf<SettingsFeature>

        private var requireSignIn: RequireSignIn? {
            store.requireSignIn
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .space8) {
                MacFormGroup(L10n.Settings.sectionSecurity) {
                    if store.shouldShowPasswordRow {
                        MacFormRow(L10n.Common.password) {
                            actionButton(L10n.MacSettings.changePassword) { store.send(.changePasswordButtonTapped) }
                        }
                    }
                    if store.shouldShowTwoFactorRow {
                        MacFormRow(L10n.TwoFactor.navigationTitle) {
                            actionButton(L10n.TwoFactor.manageButton) { store.send(.twoFactorButtonTapped) }
                        }
                    }
                    MacFormRow {
                        let detail = store.clientCertificateStatus.settingsDetail()
                        if detail.isEmpty {
                            Text(L10n.Settings.clientCertificate)
                        } else {
                            MacRowTitle(title: L10n.Settings.clientCertificate, subtitle: detail)
                        }
                    } control: {
                        actionButton(L10n.Login.manageClientCertificate) {
                            store.send(.clientCertificateButtonTapped)
                        }
                    }
                    MacSwitchRow(L10n.RequireSignIn.toggle, isOn: store.isRequiringSignIn)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Settings.requireSignInToggle)
                    if let requireSignIn {
                        MacFormRow(L10n.RequireSignIn.sectionLock) {
                            MacPopup(
                                L10n.RequireSignIn.sectionLock,
                                valueLabel: requireSignIn.lockAfter.title,
                                selection: store.requireSignIn(\.lockAfter)
                            ) {
                                ForEach(RequireSignIn.LockAfter.allCases, id: \.self) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        }
                        MacSwitchRow(
                            L10n.RequireSignIn.keepOfflineFiles,
                            isOn: store.requireSignIn(\.shouldKeepOfflineFiles)
                        )
                    }
                }
                if requireSignIn == nil {
                    MacFormFootnote(L10n.RequireSignIn.footer)
                } else {
                    MacFormFootnote(L10n.RequireSignIn.footer, L10n.RequireSignIn.keepOfflineFilesFooter)
                }
            }
            .disabled(store.isSigningOut)
        }

        private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(title, action: action)
                .buttonStyle(.macDS(.secondary, size: .small))
                .fixedSize()
        }
    }

    #Preview("Off") {
        MacFormPage {
            MacSecuritySection(store: Store(initialState: .preview) { SettingsFeature() })
        }
        .previewCanvas(.settingsPane)
        .background(Color.macCard)
    }

    #Preview("On") {
        MacFormPage {
            MacSecuritySection(store: Store(initialState: .previewRequiringSignIn) { SettingsFeature() })
        }
        .previewCanvas(.settingsPane)
        .background(Color.macCard)
    }
#endif
