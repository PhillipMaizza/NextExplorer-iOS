#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The General pane: appearance, language, default sort and what the file tables show.
    struct MacGeneralSettingsTab<Notice: View>: View {
        let showHiddenFiles: Binding<Bool>?
        @ViewBuilder let notice: () -> Notice

        @AppStorage(AppStorageKeys.renderHTMLPages) private var shouldRenderHTMLPages = false
        @AppStorage(AppStorageKeys.renderMarkdownPages) private var shouldRenderMarkdownPages = false
        @AppStorage(AppStorageKeys.showFilenameExtensions) private var shouldShowFilenameExtensions = true
        @AppStorage(AppStorageKeys.appearanceOverrideSet) private var hasAppearanceOverride = false
        @AppStorage(AppStorageKeys.prefersDarkMode) private var isDarkAppearanceOverride = false
        @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""
        @AppStorage(AppStorageKeys.defaultSortOption) private var defaultSortOption = BrowseFeature.SortOption.name
        @AppStorage(AppStorageKeys.defaultSortDirection) private var defaultSortDirection = BrowseFeature
            .SortDirection.ascending

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

        private static func languageTitle(_ code: String) -> String {
            let name = code.isEmpty ? L10n.Language.systemDefault : LocalizationOverride.displayName(for: code)
            let flagCode = code.isEmpty ? LocalizationOverride.systemLanguage : code
            guard let flag = LocalizationOverride.flag(for: flagCode) else { return name }
            return "\(flag)  \(name)"
        }

        var body: some View {
            MacFormPage {
                notice()
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroupTitle(L10n.Settings.rowAppearance)
                    MacAppearanceTiles(selection: appearance)
                }
                MacFormGroup(L10n.Settings.sectionGeneral) {
                    languageRow
                    if showHiddenFiles != nil {
                        defaultSortRow
                    }
                }
                if let showHiddenFiles {
                    MacFormGroup(L10n.Settings.sectionDisplay) {
                        MacSwitchRow(L10n.Settings.toggleShowExtensions, isOn: $shouldShowFilenameExtensions)
                        MacSwitchRow(L10n.Settings.toggleShowHiddenFiles, isOn: showHiddenFiles)
                        MacSwitchRow(L10n.Settings.toggleRenderMarkdown, isOn: $shouldRenderMarkdownPages)
                        MacSwitchRow(L10n.Settings.toggleRenderHTML, isOn: $shouldRenderHTMLPages)
                    }
                }
            }
        }

        private var languageRow: some View {
            MacFormRow(L10n.Settings.rowLanguage) {
                MacPopup(
                    L10n.Settings.rowLanguage,
                    valueLabel: Self.languageTitle(appLanguage),
                    selection: language
                ) {
                    Text(Self.languageTitle("")).tag("")
                    ForEach(LocalizationOverride.supportedLanguages, id: \.self) { code in
                        Text(Self.languageTitle(code)).tag(code)
                    }
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.languagePicker)
            }
        }

        private var defaultSortRow: some View {
            MacFormRow {
                MacRowTitle(title: L10n.Settings.rowDefaultSort, subtitle: L10n.Settings.defaultSortFooter)
            } control: {
                HStack(spacing: .space8) {
                    MacPopup(
                        L10n.Settings.rowDefaultSort,
                        valueLabel: defaultSortOption.title,
                        selection: $defaultSortOption
                    ) {
                        ForEach(BrowseFeature.SortOption.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    MacPopup(
                        L10n.Settings.rowSortOrder,
                        valueLabel: defaultSortDirection.title,
                        selection: $defaultSortDirection
                    ) {
                        ForEach(BrowseFeature.SortDirection.allCases, id: \.self) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                }
            }
        }
    }

    extension MacGeneralSettingsTab where Notice == EmptyView {
        init(store: StoreOf<SettingsFeature>) {
            self.init(
                showHiddenFiles: Bindable(store).preferences.shouldShowHiddenFiles.sending(\.setShowHiddenFiles)
            ) { EmptyView() }
        }
    }

    #Preview("General") {
        MacGeneralSettingsTab(store: Store(initialState: .macPreview) { SettingsFeature() })
            .previewCanvas(.settingsPane)
    }

    #Preview("General, locked") {
        MacGeneralSettingsTab(showHiddenFiles: nil) {
            MacNote(L10n.LockedSettings.note(User.preview.username), kind: .warning)
        }
        .previewCanvas(.settingsPane)
    }

    #Preview("General, signed out") {
        MacGeneralSettingsTab(showHiddenFiles: nil) { EmptyView() }
            .previewCanvas(.settingsPane)
    }
#endif
