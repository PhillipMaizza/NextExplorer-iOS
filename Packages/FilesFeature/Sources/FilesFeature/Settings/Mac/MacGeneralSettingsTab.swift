#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
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
                get: { AppearanceMode(hasOverride: hasAppearanceOverride, prefersDark: isDarkAppearanceOverride) },
                set: { mode in
                    hasAppearanceOverride = mode.hasOverride
                    isDarkAppearanceOverride = mode.prefersDark
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

        var body: some View {
            MacSettingsPane {
                Section(L10n.Settings.sectionGeneral) {
                    Toggle(L10n.Settings.toggleShowHiddenFiles, isOn: $store.preferences.showHiddenFiles.sending(\.setShowHiddenFiles))
                        .accessibilityLabel(L10n.Settings.toggleShowHiddenFiles)
                    Toggle(L10n.Settings.toggleShowExtensions, isOn: $shouldShowFilenameExtensions)
                        .accessibilityLabel(L10n.Settings.toggleShowExtensions)
                }
                Section(L10n.Settings.sectionDisplay) {
                    Toggle(L10n.Settings.toggleRenderHTML, isOn: $shouldRenderHTMLPages)
                        .accessibilityLabel(L10n.Settings.toggleRenderHTML)
                    Toggle(L10n.Settings.toggleRenderMarkdown, isOn: $shouldRenderMarkdownPages)
                        .accessibilityLabel(L10n.Settings.toggleRenderMarkdown)
                    Picker(L10n.Settings.rowAppearance, selection: appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker(L10n.Settings.rowLanguage, selection: language) {
                        Text(L10n.Language.systemDefault).tag("")
                        Divider()
                        ForEach(LocalizationOverride.supportedLanguages, id: \.self) { code in
                            Text(LocalizationOverride.displayName(for: code)).tag(code)
                        }
                    }
                }
            }
        }
    }

    #Preview("General") {
        MacGeneralSettingsTab(store: Store(initialState: .macPreview) { SettingsFeature() })
            .previewCanvas(.settingsPane)
    }
#endif
