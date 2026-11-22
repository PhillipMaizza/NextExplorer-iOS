#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let visibleLanguageRows = 4
        static let flagWidth: CGFloat = .size20
    }

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
        private func selectLanguage(_ code: String) {
            LocalizationOverride.apply(code.isEmpty ? nil : code)
            appLanguage = code
        }

        private var languageList: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    MacFormRows {
                        languageRow(L10n.Language.systemDefault, code: "") {
                            IconKit.web.foregroundStyle(Color.macChromeSecondary)
                        }
                        ForEach(LocalizationOverride.supportedLanguages, id: \.self) { code in
                            languageRow(LocalizationOverride.displayName(for: code), code: code) {
                                Text(LocalizationOverride.flag(for: code) ?? "")
                            }
                        }
                    }
                }
                .frame(height: MacFormMetrics.height(ofRows: Metrics.visibleLanguageRows))
                .onAppear { proxy.scrollTo(appLanguage, anchor: .center) }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.languagePicker)
        }

        private func languageRow(
            _ title: String,
            code: String,
            @ViewBuilder leading: () -> some View
        ) -> some View {
            let isSelected = appLanguage == code
            let leadingView = leading()
            return Button { selectLanguage(code) } label: {
                MacFormRow {
                    HStack(spacing: .space12) {
                        leadingView
                            .frame(width: Metrics.flagWidth)
                            .accessibilityHidden(true)
                        Text(title)
                    }
                } control: {
                    if isSelected {
                        IconKit.checkmark
                            .foregroundStyle(Color.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .id(code)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        var body: some View {
            MacFormPage {
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroupTitle(L10n.Settings.rowAppearance)
                    MacAppearanceTiles(selection: appearance)
                }
                HStack(alignment: .top, spacing: .space24) {
                    MacFormGroup(L10n.Settings.rowLanguage) {
                        languageList
                    }
                    .frame(maxWidth: .infinity)
                    MacFormGroup(L10n.Settings.sectionDisplay) {
                        MacSwitchRow(L10n.Settings.toggleShowExtensions, isOn: $shouldShowFilenameExtensions)
                        MacSwitchRow(
                            L10n.Settings.toggleShowHiddenFiles,
                            isOn: $store.preferences.shouldShowHiddenFiles.sending(\.setShowHiddenFiles)
                        )
                        MacSwitchRow(L10n.Settings.toggleRenderMarkdown, isOn: $shouldRenderMarkdownPages)
                        MacSwitchRow(L10n.Settings.toggleRenderHTML, isOn: $shouldRenderHTMLPages)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    #Preview("General") {
        MacGeneralSettingsTab(store: Store(initialState: .macPreview) { SettingsFeature() })
            .previewCanvas(.settingsPane)
    }
#endif
