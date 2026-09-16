import AppStorageKeys
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowSpacing: CGFloat = .space2
    static let checkmarkSize: CGFloat = .iconSmall
    static let checkmarkSpringResponse: Double = 0.3
    static let checkmarkSpringDamping: Double = 0.7
}

/// Pushed from Settings' "Language" row: "System Default" plus every supported UI language shown
/// by its own name (endonym). Writing the choice to `AppStorageKeys.appLanguage` is all that's
/// needed — the app root observes it, points `LocalizationOverride` at the chosen language and
/// rebuilds, so the switch takes effect live without a relaunch.
struct LanguagePickerView: View {
    @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""

    var body: some View {
        List {
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
        Button {
            // Point the bundle at the new language BEFORE writing `appLanguage`, so the rebuild the
            // write triggers (the app root re-ids on this value) already resolves `tr()` through the
            // new `.lproj`. Applying only in the root's `onChange` fires after that rebuild has
            // rendered with the old bundle, leaving the UI in the previous language.
            LocalizationOverride.apply(code.isEmpty ? nil : code)
            appLanguage = code
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Constants.rowSpacing) {
                    Text(title).type(.body1(.regular), style: .primaryOnSurface)
                    if let subtitle {
                        Text(subtitle).type(.body3(.regular), style: .secondary)
                    }
                }
                Spacer()
                if code == appLanguage {
                    IconKit.checkmark
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.accent)
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: Constants.checkmarkSpringResponse, dampingFraction: Constants.checkmarkSpringDamping), value: appLanguage)
    }
}

#Preview {
    NavigationStack {
        LanguagePickerView()
    }
}
