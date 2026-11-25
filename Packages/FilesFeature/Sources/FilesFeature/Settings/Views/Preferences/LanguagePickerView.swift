import AppStorageKeys
import DesignSystem
import Localization
import SwiftUI

/// Pushed from Settings' "Language" row: "System Default" plus every supported UI language shown
/// by its own name (endonym). Writing the choice to `AppStorageKeys.appLanguage` is all that's
/// needed: the app root observes it, points `LocalizationOverride` at the chosen language and
/// rebuilds, so the switch takes effect live without a relaunch.
struct LanguagePickerView: View {
    @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""

    var body: some View {
        DSGroupedList {
            Section {
                row(code: "", title: L10n.Language.systemDefault, subtitle: L10n.Language.systemDefaultSubtitle)
            }
            .listRowBackground(Color.backgroundSecondary)

            Section {
                ForEach(LocalizationOverride.supportedLanguages, id: \.self) { code in
                    row(code: code, title: LocalizationOverride.displayName(for: code), subtitle: nil)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .navigationTitle(L10n.Language.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .hapticFeedback(.selection, trigger: appLanguage)
    }

    private func row(code: String, title: String, subtitle: String?) -> some View {
        SettingsCheckRow(title: title, subtitle: subtitle, isSelected: code == appLanguage) {
            // Point the bundle at the new language BEFORE writing `appLanguage`, so the rebuild the
            // write triggers (the app root re ids on this value) already resolves `tr()` through the
            // new `.lproj`. Applying only in the root's `onChange` fires after that rebuild has
            // rendered with the old bundle, leaving the UI in the previous language.
            LocalizationOverride.apply(code.isEmpty ? nil : code)
            appLanguage = code
        }
    }
}

#Preview {
    NavigationStack {
        LanguagePickerView()
    }
}
