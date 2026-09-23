import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconSmall
    static let footerTopPadding: CGFloat = .space8
    static let versionLogoSize: CGFloat = .iconMedium
    static let versionLogoSpacing: CGFloat = .zero
    static let fullOpacity: Double = 1.0
    static let disabledOpacity: Double = 0.5
}

/// View-local settings search: hides individual preference rows, and whole sections once none
/// of their rows match. Empty query shows everything and re-reveals the contextual sections.
struct SettingsSearchFilter {
    let query: String

    var isActive: Bool {
        !query.isEmpty
    }

    /// Whether a row/section with this label should show for the current search.
    func matches(_ label: String) -> Bool {
        query.isEmpty || label.localizedCaseInsensitiveContains(query)
    }

    /// True when the query is empty or at least one of `labels` matches — used to drop a whole
    /// section (and its header) once none of its rows match.
    func anyMatch(_ labels: [String]) -> Bool {
        labels.contains(where: matches)
    }
}

@MainActor
enum SettingsFormat {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

@MainActor
private func sectionHeader(_ title: String) -> some View {
    DSFieldLabel(title)
        .accessibilityAddTraits(.isHeader)
}

// MARK: General

struct GeneralSettingsSection: View {
    @Bindable var store: StoreOf<SettingsFeature>
    let filter: SettingsSearchFilter

    @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @AppStorage(AppStorageKeys.renderHTMLPages) private var renderHTMLPages = false
    @AppStorage(AppStorageKeys.renderMarkdownPages) private var renderMarkdownPages = false
    @AppStorage(AppStorageKeys.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""

    private var currentLanguageLabel: String {
        appLanguage.isEmpty ? L10n.Language.systemDefault : LocalizationOverride.displayName(for: appLanguage)
    }

    private var dateFormat: Binding<DateDisplayFormat> {
        Binding(
            get: { DateDisplayFormat(rawValue: dateFormatRaw) ?? .system },
            set: { dateFormatRaw = $0.rawValue }
        )
    }

    var body: some View {
        if filter.anyMatch([L10n.Settings.toggleShowHiddenFiles, L10n.Settings.toggleRenderHTML, L10n.Settings.toggleRenderMarkdown, L10n.Settings.rowDateFormat, L10n.Settings.rowLanguage, L10n.Settings.toggleHaptics]) {
            Section {
                if filter.matches(L10n.Settings.toggleShowHiddenFiles) {
                    DSToggleRow(
                        title: L10n.Settings.toggleShowHiddenFiles,
                        icon: IconKit.eye,
                        isOn: $store.preferences.showHiddenFiles.sending(\.setShowHiddenFiles)
                    )
                }
                if filter.matches(L10n.Settings.toggleRenderHTML) {
                    DSToggleRow(title: L10n.Settings.toggleRenderHTML, icon: IconKit.web, isOn: $renderHTMLPages)
                }
                if filter.matches(L10n.Settings.toggleRenderMarkdown) {
                    DSToggleRow(title: L10n.Settings.toggleRenderMarkdown, icon: IconKit.textformat, isOn: $renderMarkdownPages)
                }
                if filter.matches(L10n.Settings.rowDateFormat) {
                    NavigationLink {
                        DateFormatPickerView(selection: dateFormat)
                    } label: {
                        Label {
                            HStack {
                                Text(L10n.Settings.rowDateFormat).type(.body2(.regular), style: .primaryOnSurface)
                                Spacer()
                                Text(dateFormat.wrappedValue.title).type(.body2(.regular), style: .secondary)
                            }
                        } icon: {
                            IconKit.calendar
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                }
                if filter.matches(L10n.Settings.rowLanguage) {
                    NavigationLink {
                        LanguagePickerView()
                    } label: {
                        Label {
                            HStack {
                                Text(L10n.Settings.rowLanguage).type(.body2(.regular), style: .primaryOnSurface)
                                Spacer()
                                Text(currentLanguageLabel).type(.body2(.regular), style: .secondary)
                            }
                        } icon: {
                            IconKit.language
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                }
                #if os(iOS)
                    if filter.matches(L10n.Settings.toggleHaptics) {
                        DSToggleRow(title: L10n.Settings.toggleHaptics, icon: IconKit.haptics, isOn: $hapticsEnabled)
                    }
                #endif
            } header: {
                sectionHeader(L10n.Settings.sectionGeneral)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}

// MARK: Display

struct DisplaySettingsSection: View {
    @Bindable var store: StoreOf<SettingsFeature>
    let filter: SettingsSearchFilter

    @AppStorage(AppStorageKeys.appearanceOverrideSet) private var hasAppearanceOverride = false
    @AppStorage(AppStorageKeys.prefersDarkMode) private var prefersDarkModeOverride = false
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue
    @AppStorage(AppStorageKeys.showFilenameExtensions) private var showFilenameExtensions = true
    @AppStorage(AppStorageKeys.showTabLabels) private var showTabLabels = false
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isDarkModeOn: Binding<Bool> {
        Binding(
            get: { hasAppearanceOverride ? prefersDarkModeOverride : systemColorScheme == .dark },
            set: { newValue in
                hasAppearanceOverride = true
                prefersDarkModeOverride = newValue
            }
        )
    }

    private var thumbnailSize: Binding<ThumbnailSize> {
        Binding(
            get: { ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium },
            set: { thumbnailSizeRaw = $0.rawValue }
        )
    }

    var body: some View {
        if filter.anyMatch([L10n.Settings.toggleDarkMode, L10n.Settings.toggleShowThumbnails, L10n.Settings.rowThumbnailSize, L10n.Settings.toggleShowExtensions, L10n.Settings.toggleShowTabLabels]) {
            Section {
                if filter.matches(L10n.Settings.toggleDarkMode) {
                    DSToggleRow(title: L10n.Settings.toggleDarkMode, icon: IconKit.darkMode, isOn: isDarkModeOn)
                }
                if filter.matches(L10n.Settings.toggleShowThumbnails) {
                    DSToggleRow(
                        title: L10n.Settings.toggleShowThumbnails,
                        icon: IconKit.photo,
                        isOn: $store.preferences.showThumbnails.sending(\.setShowThumbnails)
                    )
                }
                if filter.matches(L10n.Settings.rowThumbnailSize) {
                    Picker(selection: thumbnailSize) {
                        ForEach(ThumbnailSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    } label: {
                        Label {
                            Text(L10n.Settings.rowThumbnailSize).type(.body2(.regular), style: .primaryOnSurface)
                        } icon: {
                            IconKit.squareGrid
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.secondaryDS)
                    .hapticFeedback(.selection, trigger: thumbnailSizeRaw)
                }
                if filter.matches(L10n.Settings.toggleShowExtensions) {
                    DSToggleRow(title: L10n.Settings.toggleShowExtensions, icon: IconKit.tag, isOn: $showFilenameExtensions)
                }
                // Tab labels only exist on the bottom tab bar (compact). iPad uses the sidebar,
                // so the toggle is meaningless there.
                if horizontalSizeClass != .regular, filter.matches(L10n.Settings.toggleShowTabLabels) {
                    DSToggleRow(title: L10n.Settings.toggleShowTabLabels, icon: IconKit.tabBrowse, isOn: $showTabLabels)
                }
            } header: {
                sectionHeader(L10n.Settings.sectionDisplay)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}

// MARK: Storage

struct StorageSettingsSection: View {
    let store: StoreOf<SettingsFeature>
    let filter: SettingsSearchFilter

    @AppStorage(AppStorageKeys.removeArchiveAfterDownload) private var removeArchiveAfterDownload = false
    @AppStorage(AppStorageKeys.keepClipboardAfterCopy) private var keepClipboardAfterCopy = false

    var body: some View {
        if filter.anyMatch([L10n.Settings.toggleRemoveArchives, L10n.Settings.toggleKeepClipboard, L10n.Settings.rowRemoveAllDownloads, L10n.Settings.rowClearCache]) {
            Section {
                if filter.matches(L10n.Settings.toggleRemoveArchives) {
                    DSToggleRow(title: L10n.Settings.toggleRemoveArchives, icon: IconKit.archivePage, isOn: $removeArchiveAfterDownload)
                }
                if filter.matches(L10n.Settings.toggleKeepClipboard) {
                    DSToggleRow(
                        title: L10n.Settings.toggleKeepClipboard,
                        subtitle: L10n.Settings.toggleKeepClipboardSubtitle,
                        icon: IconKit.paste,
                        isOn: $keepClipboardAfterCopy
                    )
                }
                if filter.matches(L10n.Settings.rowRemoveAllDownloads) {
                    DSNavigationRow(
                        title: L10n.Settings.rowRemoveAllDownloads,
                        icon: IconKit.delete,
                        accessory: .detail(SettingsFormat.byteFormatter.string(fromByteCount: store.downloadsSize)),
                        role: .accent
                    ) {
                        store.send(.removeAllDownloadsTapped)
                    }
                    .disabled(store.isRemovingAllDownloads || !store.hasDownloads)
                    .opacity(store.hasDownloads ? Constants.fullOpacity : Constants.disabledOpacity)
                }
                if filter.matches(L10n.Settings.rowClearCache) {
                    DSNavigationRow(
                        title: L10n.Settings.rowClearCache,
                        icon: IconKit.delete,
                        accessory: .detail(SettingsFormat.byteFormatter.string(fromByteCount: store.cacheSize)),
                        role: .accent
                    ) {
                        store.send(.clearCacheTapped)
                    }
                    .disabled(store.isClearingCache || store.cacheSize == 0)
                    .opacity(store.cacheSize > 0 ? Constants.fullOpacity : Constants.disabledOpacity)
                }
            } header: {
                sectionHeader(L10n.Settings.sectionStorage)
            } footer: {
                if !filter.isActive {
                    Text(L10n.Settings.storageFootnote)
                        .type(.body3(.regular), style: .tertiary)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}

// MARK: Legal

struct LegalSettingsSection: View {
    let filter: SettingsSearchFilter

    @Environment(\.openURL) private var openURL

    /// Hosted alongside the app's site. Update these if the pages move.
    private enum Links {
        static let privacy = "https://phillipmaizza.com/nextexplorer/privacy.html"
        static let terms = "https://phillipmaizza.com/nextexplorer/terms.html"
    }

    var body: some View {
        if filter.anyMatch([L10n.Settings.rowPrivacyPolicy, L10n.Settings.rowTermsOfUse]) {
            Section {
                if filter.matches(L10n.Settings.rowPrivacyPolicy) {
                    legalRow(title: L10n.Settings.rowPrivacyPolicy, icon: IconKit.shield, link: Links.privacy)
                }
                if filter.matches(L10n.Settings.rowTermsOfUse) {
                    legalRow(title: L10n.Settings.rowTermsOfUse, icon: IconKit.document, link: Links.terms)
                }
            } header: {
                sectionHeader(L10n.Settings.sectionLegal)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private func legalRow(title: String, icon: Image, link: String) -> some View {
        Button {
            if let url = URL(string: link) {
                openURL(url)
            }
        } label: {
            Label {
                HStack {
                    Text(title).type(.body2(.regular), style: .primaryOnSurface)
                    Spacer()
                    IconKit.externalLink
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: .iconXSmall, height: .iconXSmall)
                }
            } icon: {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: Licenses

struct LicensesSettingsSection: View {
    @Bindable var store: StoreOf<SettingsFeature>
    let filter: SettingsSearchFilter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return L10n.Settings.appVersion(version, build)
    }

    /// "Like the app? Buy me a coffee ☕️" as one wrapping line. Only the coffee half is bold and
    /// accented so it reads as the tappable part; the lead-in stays regular weight.
    private var tipPrompt: Text {
        Text(L10n.Settings.creditsLikeApp + " ").fontWeight(.regular)
            + Text(L10n.Settings.creditsBuyCoffee).fontWeight(.bold).foregroundColor(.accent)
    }

    var body: some View {
        if filter.anyMatch([L10n.Settings.rowOpenSourceLicenses]) {
            Section {
                if filter.matches(L10n.Settings.rowOpenSourceLicenses) {
                    NavigationLink {
                        LicensesView()
                    } label: {
                        Label {
                            Text(L10n.Settings.rowOpenSourceLicenses).type(.body2(.regular), style: .primaryOnSurface)
                        } icon: {
                            IconKit.document
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                }
            } header: {
                sectionHeader(L10n.Settings.sectionLicenses)
            } footer: {
                if !filter.isActive {
                    VStack(spacing: .space16) {
                        // On iPad the logo + version live in the sidebar footer instead, so this
                        // section only carries the credits there; compact keeps the full block.
                        if horizontalSizeClass != .regular {
                            VStack(spacing: Constants.versionLogoSpacing) {
                                IconKit.logo
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: Constants.versionLogoSize, height: Constants.versionLogoSize)
                                Text(appVersionText)
                                    .type(.label4, style: .tertiary)
                            }
                        }
                        VStack(spacing: .space4) {
                            // `.body3(.regular)` is the same 14pt/subheadline metrics as label4 but
                            // regular weight (label4 is semibold, and `.type` bakes that weight in
                            // too close to the Text for an outer `.fontWeight` to override).
                            Text(L10n.Settings.creditsMadeBy)
                                .type(.body3(.regular), style: .tertiary)
                            Button {
                                store.send(.tipJarButtonTapped)
                            } label: {
                                tipPrompt.type(.label4, style: .tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Constants.footerTopPadding)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }
}
