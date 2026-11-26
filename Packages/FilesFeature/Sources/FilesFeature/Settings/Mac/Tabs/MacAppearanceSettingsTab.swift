#if os(macOS)
    import AppStorageKeys
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let visibleLanguageRows = 6
        static let flagWidth: CGFloat = .size20
    }

    struct MacAppearanceSettingsTab<Notice: View>: View {
        @ViewBuilder let notice: () -> Notice

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

        var body: some View {
            MacFormPage {
                notice()
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroupTitle(L10n.Settings.groupTheme)
                    MacAppearanceTiles(selection: appearance)
                }
                MacFormGroup(L10n.Settings.rowLanguage) {
                    languageList
                }
            }
        }

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
    }

    extension MacAppearanceSettingsTab where Notice == EmptyView {
        init() {
            self.init { EmptyView() }
        }
    }

    #Preview("Appearance") {
        MacAppearanceSettingsTab()
            .previewCanvas(.settingsPane)
    }

    #Preview("Appearance, locked") {
        MacAppearanceSettingsTab {
            MacNote(L10n.LockedSettings.note(User.preview.username), kind: .warning)
        }
        .previewCanvas(.settingsPane)
    }
#endif
