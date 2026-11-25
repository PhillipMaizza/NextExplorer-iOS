import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

struct RequireSignInView: View {
    let store: StoreOf<SettingsFeature>

    private var requireSignIn: RequireSignIn? {
        store.requireSignIn
    }

    var body: some View {
        DSGroupedList {
            Section {
                DSToggleRow(title: L10n.RequireSignIn.toggle, icon: IconKit.key, isOn: store.isRequiringSignIn)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.requireSignInToggle)
            } footer: {
                Text(L10n.RequireSignIn.footer)
                    .type(.body3(.regular), style: .tertiary)
            }
            .listRowBackground(Color.backgroundSecondary)

            if let requireSignIn {
                Section {
                    ForEach(RequireSignIn.LockAfter.allCases, id: \.self) { lockAfter in
                        SettingsCheckRow(title: lockAfter.title, isSelected: lockAfter == requireSignIn.lockAfter) {
                            store.requireSignIn(\.lockAfter).wrappedValue = lockAfter
                        }
                    }
                } header: {
                    SettingsSectionHeader(L10n.RequireSignIn.sectionLock)
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    DSToggleRow(
                        title: L10n.RequireSignIn.keepOfflineFiles,
                        icon: IconKit.availableOffline,
                        isOn: store.requireSignIn(\.shouldKeepOfflineFiles)
                    )
                } footer: {
                    Text(L10n.RequireSignIn.keepOfflineFilesFooter)
                        .type(.body3(.regular), style: .tertiary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .navigationTitle(L10n.RequireSignIn.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .hapticFeedback(.selection, trigger: requireSignIn)
        .animation(DSMotion.disclosure, value: requireSignIn != nil)
    }
}

#Preview("Off") {
    NavigationStack {
        RequireSignInView(store: Store(initialState: .preview) { SettingsFeature() })
    }
}

#Preview("On") {
    NavigationStack {
        RequireSignInView(store: Store(initialState: .previewRequiringSignIn) { SettingsFeature() })
    }
}
