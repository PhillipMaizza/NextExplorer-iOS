#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import Localization
    import SwiftUI

    /// The General pane: what the file tables show, and the app's appearance and language.
    struct MacGeneralSettingsTab: View {
        @Bindable var store: StoreOf<SettingsFeature>

        @AppStorage(AppStorageKeys.renderHTMLPages) private var renderHTMLPages = false
        @AppStorage(AppStorageKeys.renderMarkdownPages) private var renderMarkdownPages = false
        @AppStorage(AppStorageKeys.showFilenameExtensions) private var showFilenameExtensions = true
        @AppStorage(AppStorageKeys.appearanceOverrideSet) private var hasAppearanceOverride = false
        @AppStorage(AppStorageKeys.prefersDarkMode) private var prefersDarkModeOverride = false
        @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""

        private var appearance: Binding<AppearanceMode> {
            Binding(
                get: { AppearanceMode(hasOverride: hasAppearanceOverride, prefersDark: prefersDarkModeOverride) },
                set: { mode in
                    hasAppearanceOverride = mode.hasOverride
                    prefersDarkModeOverride = mode.prefersDark
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
                    Toggle(L10n.Settings.toggleShowExtensions, isOn: $showFilenameExtensions)
                }
                Section(L10n.Settings.sectionDisplay) {
                    Toggle(L10n.Settings.toggleRenderHTML, isOn: $renderHTMLPages)
                    Toggle(L10n.Settings.toggleRenderMarkdown, isOn: $renderMarkdownPages)
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
            .frame(width: 640, height: 400)
    }
#endif
