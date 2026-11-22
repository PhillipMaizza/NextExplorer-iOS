#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The General pane: what the file tables show, and the app's appearance and language.
    struct MacGeneralSettingsTab: View {
        @Bindable var store: StoreOf<SettingsFeature>

        @AppStorage(AppStorageKeys.renderHTMLPages) private var shouldRenderHTMLPages = false
        @AppStorage(AppStorageKeys.renderMarkdownPages) private var shouldRenderMarkdownPages = false
        @AppStorage(AppStorageKeys.showFilenameExtensions) private var shouldShowFilenameExtensions = true
        @AppStorage(AppStorageKeys.appearanceOverrideSet) private var hasAppearanceOverride = false
        @AppStorage(AppStorageKeys.prefersDarkMode) private var isDarkAppearanceOverride = false
        @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""

        private var appearance: Binding<AppearanceMode> {
            Binding(
                get: { AppearanceMode(hasOverride: hasAppearanceOverride, isDark: isDarkAppearanceOverride) },
                set: { mode in
                    hasAppearanceOverride = mode.hasOverride
                    isDarkAppearanceOverride = mode.isDark
                }
            )
        }

        /// Points the bundle at the new language before writing it, so the rebuild the write
        /// triggers already reads the new strings (see `LanguagePickerView`).
        private var language: Binding<String> {
            Binding(
                get: { appLanguage },
                set: { code in
                    LocalizationOverride.apply(code.isEmpty ? nil : code)
                    appLanguage = code
                }
            )
        }

        private var languageLabel: String {
            appLanguage.isEmpty ? L10n.Language.systemDefault : LocalizationOverride.displayName(for: appLanguage)
        }

        var body: some View {
            MacFormPage {
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroupTitle(L10n.Settings.rowAppearance)
                    MacAppearanceTiles(selection: appearance)
                }
                HStack(alignment: .top, spacing: .space24) {
                    MacFormGroup(L10n.Settings.sectionGeneral) {
                        MacFormRow(L10n.Settings.rowLanguage) {
                            MacPopup(L10n.Settings.rowLanguage, valueLabel: languageLabel, selection: language) {
                                Text(L10n.Language.systemDefault).tag("")
                                Divider()
                                ForEach(LocalizationOverride.supportedLanguages, id: \.self) { code in
                                    Text(LocalizationOverride.displayName(for: code)).tag(code)
                                }
                            }
                            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.languagePicker)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    MacFormGroup(L10n.Settings.sectionDisplay) {
                        switchRow(L10n.Settings.toggleShowExtensions, isOn: $shouldShowFilenameExtensions)
                        switchRow(
                            L10n.Settings.toggleShowHiddenFiles,
                            isOn: $store.preferences.shouldShowHiddenFiles.sending(\.setShowHiddenFiles)
                        )
                        switchRow(L10n.Settings.toggleRenderMarkdown, isOn: $shouldRenderMarkdownPages)
                        switchRow(L10n.Settings.toggleRenderHTML, isOn: $shouldRenderHTMLPages)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }

        private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
            MacFormRow(title) {
                Toggle(title, isOn: isOn).labelsHidden()
            }
        }
    }

    #Preview("General") {
        MacGeneralSettingsTab(store: Store(initialState: .macPreview) { SettingsFeature() })
            .previewCanvas(.settingsPane)
    }
#endif
