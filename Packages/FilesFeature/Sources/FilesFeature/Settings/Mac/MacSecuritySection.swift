#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import Localization
    import SwiftUI

    struct MacSecuritySection: View {
        let store: StoreOf<SettingsFeature>

        private var requireSignIn: RequireSignIn? {
            store.requireSignIn
        }

        var body: some View {
            Section {
                if store.shouldShowPasswordRow {
                    LabeledContent(L10n.Settings.rowChangePassword) {
                        Button(L10n.MacSettings.changePassword) { store.send(.changePasswordButtonTapped) }
                    }
                }
                if store.shouldShowTwoFactorRow {
                    LabeledContent(L10n.TwoFactor.navigationTitle) {
                        Button(L10n.TwoFactor.manageButton) { store.send(.twoFactorButtonTapped) }
                    }
                }
                Toggle(L10n.RequireSignIn.toggle, isOn: store.isRequiringSignIn)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.requireSignInToggle)
                if requireSignIn != nil {
                    Picker(L10n.RequireSignIn.sectionLock, selection: store.requireSignIn(\.lockAfter)) {
                        ForEach(RequireSignIn.LockAfter.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Toggle(L10n.RequireSignIn.keepOfflineFiles, isOn: store.requireSignIn(\.shouldKeepOfflineFiles))
                }
            } header: {
                Text(L10n.Settings.sectionSecurity)
            } footer: {
                if requireSignIn == nil {
                    MacSectionFooter(L10n.RequireSignIn.footer)
                } else {
                    MacSectionFooter(L10n.RequireSignIn.footer, L10n.RequireSignIn.keepOfflineFilesFooter)
                }
            }
            .disabled(store.isSigningOut)
        }
    }

    #Preview("Off") {
        MacSettingsPane {
            MacSecuritySection(store: Store(initialState: .preview) { SettingsFeature() })
        }
    }

    #Preview("On") {
        MacSettingsPane {
            MacSecuritySection(store: Store(initialState: .previewRequiringSignIn) { SettingsFeature() })
        }
    }
#endif
