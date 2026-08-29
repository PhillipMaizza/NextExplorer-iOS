import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let avatarSize: CGFloat = .size48
    static let profileRowSpacing: CGFloat = .space12
    static let rowIconSize: CGFloat = .iconSmall
    static let rowIconSpacing: CGFloat = .space8
    static let serverLogoSize: CGFloat = .iconMedium
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space4
    static let tagBorderWidth: CGFloat = 1
    static let footerTopPadding: CGFloat = .space8
    static let signOutFadeDuration: Double = 0.15
    static let fullOpacity: Double = 1.0
    static let disabledOpacity: Double = 0.5
}

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    /// One toast host for the whole Settings navigation stack. User Management raises success
    /// messages from two levels down (the list and the pushed user detail); hosting the toast
    /// here, above every `.navigationDestination`, is the only spot a bottom overlay isn't
    /// occluded by a pushed screen, so those two views don't each need their own.
    @State private var userManagementToast: DSToastMessage?

    /// Falls back to whatever the system currently resolves to until the user has
    /// explicitly overridden it, so the toggle starts in sync with the system, exactly
    /// once, rather than carrying its own separate "system" state.
    @AppStorage("hasSetAppearanceOverride") private var hasAppearanceOverride = false
    @AppStorage("prefersDarkMode") private var prefersDarkModeOverride = false
    @AppStorage("dateDisplayFormat") private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue
    @AppStorage("renderHTMLPages") private var renderHTMLPages = false
    @AppStorage("renderMarkdownPages") private var renderMarkdownPages = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("showFilenameExtensions") private var showFilenameExtensions = true
    @AppStorage("removeArchiveAfterDownload") private var removeArchiveAfterDownload = false
    @AppStorage("keepClipboardAfterCopy") private var keepClipboardAfterCopy = false
    @Environment(\.colorScheme) private var systemColorScheme

    private var isDarkModeOn: Binding<Bool> {
        Binding(
            get: { hasAppearanceOverride ? prefersDarkModeOverride : systemColorScheme == .dark },
            set: { newValue in
                hasAppearanceOverride = true
                prefersDarkModeOverride = newValue
            }
        )
    }

    private var dateFormat: Binding<DateDisplayFormat> {
        Binding(
            get: { DateDisplayFormat(rawValue: dateFormatRaw) ?? .system },
            set: { dateFormatRaw = $0.rawValue }
        )
    }

    private var thumbnailSize: Binding<ThumbnailSize> {
        Binding(
            get: { ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium },
            set: { thumbnailSizeRaw = $0.rawValue }
        )
    }

    private var isConfirmingSignOut: Binding<Bool> {
        Binding(
            get: { store.isConfirmingSignOut },
            set: { isPresented in
                if !isPresented { store.send(.cancelSignOutTapped) }
            }
        )
    }

    private var isConfirmingRemoveAllDownloads: Binding<Bool> {
        Binding(
            get: { store.removeAllDownloadsConfirmationIsPresented },
            set: { isPresented in
                if !isPresented { store.send(.removeAllDownloadsCancelled) }
            }
        )
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var isConfirmingClearCache: Binding<Bool> {
        Binding(
            get: { store.clearCacheConfirmationIsPresented },
            set: { isPresented in
                if !isPresented { store.send(.clearCacheCancelled) }
            }
        )
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return L10n.Settings.appVersion(version, build)
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection

                Section {
                    DSToggleRow(
                        title: L10n.Settings.toggleShowHiddenFiles,
                        icon: IconKit.eye,
                        isOn: $store.preferences.showHiddenFiles.sending(\.setShowHiddenFiles)
                    )
                    DSToggleRow(
                        title: L10n.Settings.toggleRenderHTML,
                        icon: IconKit.web,
                        isOn: $renderHTMLPages
                    )
                    DSToggleRow(
                        title: L10n.Settings.toggleRenderMarkdown,
                        icon: IconKit.textformat,
                        isOn: $renderMarkdownPages
                    )
                    NavigationLink {
                        DateFormatPickerView(selection: dateFormat)
                    } label: {
                        Label {
                            HStack {
                                Text(L10n.Settings.rowDateFormat).type(.body2(.regular), style: .primary(for: .label))
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
                    DSToggleRow(
                        title: L10n.Settings.toggleHaptics,
                        icon: IconKit.haptics,
                        isOn: $hapticsEnabled
                    )
                } header: {
                    sectionHeader(L10n.Settings.sectionGeneral)
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    DSToggleRow(title: L10n.Settings.toggleDarkMode, icon: IconKit.darkMode, isOn: isDarkModeOn)
                    DSToggleRow(
                        title: L10n.Settings.toggleShowThumbnails,
                        icon: IconKit.photo,
                        isOn: $store.preferences.showThumbnails.sending(\.setShowThumbnails)
                    )
                    Picker(selection: thumbnailSize) {
                        ForEach(ThumbnailSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    } label: {
                        Label {
                            Text(L10n.Settings.rowThumbnailSize).type(.body2(.regular), style: .primary(for: .label))
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
                    DSToggleRow(
                        title: L10n.Settings.toggleShowExtensions,
                        icon: IconKit.tag,
                        isOn: $showFilenameExtensions
                    )
                } header: {
                    sectionHeader(L10n.Settings.sectionDisplay)
                }
                .listRowBackground(Color.backgroundSecondary)

                usersSection

                serverAdminSection

                serverStorageSection

                Section {
                    DSToggleRow(
                        title: L10n.Settings.toggleRemoveArchives,
                        icon: IconKit.archivePage,
                        isOn: $removeArchiveAfterDownload
                    )
                    DSToggleRow(
                        title: L10n.Settings.toggleKeepClipboard,
                        subtitle: L10n.Settings.toggleKeepClipboardSubtitle,
                        icon: IconKit.paste,
                        isOn: $keepClipboardAfterCopy
                    )
                    DSNavigationRow(
                        title: L10n.Settings.rowRemoveAllDownloads,
                        icon: IconKit.delete,
                        accessory: .detail(Self.byteFormatter.string(fromByteCount: store.downloadsSize)),
                        role: .accent
                    ) {
                        store.send(.removeAllDownloadsTapped)
                    }
                    .disabled(store.isRemovingAllDownloads || !store.hasDownloads)
                    DSNavigationRow(
                        title: L10n.Settings.rowClearCache,
                        icon: IconKit.delete,
                        accessory: .detail(Self.byteFormatter.string(fromByteCount: store.cacheSize)),
                        role: .accent
                    ) {
                        store.send(.clearCacheTapped)
                    }
                    .disabled(store.isClearingCache || store.cacheSize == 0)
                } header: {
                    sectionHeader(L10n.Settings.sectionStorage)
                } footer: {
                    Text(L10n.Settings.storageFootnote)
                        .type(.body3(.regular), style: .tertiary)
                }
                .listRowBackground(Color.backgroundSecondary)

                Section {
                    NavigationLink {
                        LicensesView()
                    } label: {
                        Label {
                            Text(L10n.Settings.rowOpenSourceLicenses).type(.body2(.regular), style: .primary(for: .label))
                        } icon: {
                            IconKit.document
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                        }
                    }
                } header: {
                    sectionHeader(L10n.Settings.sectionLicenses)
                } footer: {
                    Text(appVersionText)
                        .type(.label4, style: .tertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, Constants.footerTopPadding)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .navigationDestination(
                item: $store.scope(state: \.userManagement, action: \.userManagement)
            ) { userManagementStore in
                UserManagementView(store: userManagementStore)
            }
            .navigationDestination(
                item: $store.scope(state: \.changePassword, action: \.changePassword)
            ) { changePasswordStore in
                ChangePasswordView(store: changePasswordStore)
            }
            .navigationDestination(
                item: $store.scope(state: \.serverDetails, action: \.serverDetails)
            ) { serverDetailsStore in
                ServerDetailsView(store: serverDetailsStore)
            }
            .navigationDestination(
                item: $store.scope(state: \.thumbnailSettings, action: \.thumbnailSettings)
            ) { thumbnailStore in
                ThumbnailSettingsView(store: thumbnailStore)
            }
            .navigationDestination(
                item: $store.scope(state: \.accessRules, action: \.accessRules)
            ) { accessRulesStore in
                AccessRulesView(store: accessRulesStore)
            }
            .navigationTitle(L10n.Settings.navigationTitle)
            // `.alert`, not `.confirmationDialog`: a confirmationDialog presents as a
            // popover anchored to some ambient source view on the `.pad` idiom (this app
            // also targets iPad) rather than a full-width bottom sheet. `.alert` is always
            // a centered modal regardless of idiom, so there's no anchor to get wrong.
            .alert(L10n.Settings.signOutAlertTitle, isPresented: isConfirmingSignOut) {
                Button(L10n.Common.logOut, role: .destructive) { store.send(.confirmSignOutTapped) }
                Button(L10n.Common.cancel, role: .cancel) { store.send(.cancelSignOutTapped) }
            } message: {
                Text(L10n.Settings.signOutMessage)
            }
            .alert(L10n.Settings.removeAllDownloadsTitle, isPresented: isConfirmingRemoveAllDownloads) {
                Button(L10n.Settings.removeAllDownloadsConfirm, role: .destructive) { store.send(.removeAllDownloadsConfirmed) }
                Button(L10n.Common.cancel, role: .cancel) { store.send(.removeAllDownloadsCancelled) }
            } message: {
                Text(L10n.Settings.removeAllDownloadsMessage)
            }
            .hapticFeedback(.warning, trigger: store.removeAllDownloadsConfirmationIsPresented)
            .alert(L10n.Settings.clearCacheTitle, isPresented: isConfirmingClearCache) {
                Button(L10n.Settings.clearCacheConfirm, role: .destructive) { store.send(.clearCacheConfirmed) }
                Button(L10n.Common.cancel, role: .cancel) { store.send(.clearCacheCancelled) }
            } message: {
                Text(L10n.Settings.clearCacheMessage)
            }
            .hapticFeedback(.warning, trigger: store.clearCacheConfirmationIsPresented)
            .task {
                store.send(.onAppear)
            }
        }
        .tint(Color.accent)
        .dsToast(userManagementToastBinding)
        .onChange(of: store.userManagement?.toast) { _, toast in
            guard let toast else { return }
            userManagementToast = .success(toast)
        }
    }

    private var userManagementToastBinding: Binding<DSToastMessage?> {
        Binding(
            get: { userManagementToast },
            set: { newValue in
                userManagementToast = newValue
                if newValue == nil { store.send(.userManagement(.presented(.toastDismissed))) }
            }
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        DSFieldLabel(title)
    }

    @ViewBuilder
    private var usersSection: some View {
        if store.user.isAdmin {
            Section {
                DSNavigationRow(title: L10n.Settings.rowUserManagement, icon: IconKit.people) {
                    store.send(.userManagementButtonTapped)
                }
            } header: {
                sectionHeader(L10n.Settings.sectionUsers)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    /// Admin-only server config that isn't per-user: thumbnail generation and folder access
    /// rules, each a pushed detail screen. Mirrors the web client's admin settings pages.
    @ViewBuilder
    private var serverAdminSection: some View {
        if store.user.isAdmin {
            Section {
                DSNavigationRow(title: L10n.Settings.rowThumbnails, icon: IconKit.photo) {
                    store.send(.thumbnailSettingsButtonTapped)
                }
                DSNavigationRow(title: L10n.Settings.rowAccessRules, icon: IconKit.shield) {
                    store.send(.accessRulesButtonTapped)
                }
            } header: {
                sectionHeader(L10n.Settings.sectionAdmin)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    /// One disk-usage bar per volume — iOS's take on the web client's volume list. Only
    /// present when the server reports `volumeUsage.enabled` and has returned volumes.
    @ViewBuilder
    private var serverStorageSection: some View {
        if store.isVolumeUsageEnabled && !store.serverUsage.isEmpty {
            Section {
                ForEach(store.serverUsage) { row in
                    VStack(alignment: .leading, spacing: .space8) {
                        HStack {
                            Text(row.volume.name).type(.body2(.regular), style: .primary(for: .label))
                            Spacer()
                            if let usage = row.usage, usage.isMeaningful {
                                Text(usageCaption(usage)).type(.body3(.regular), style: .secondary)
                            } else if row.usage == nil {
                                ProgressView().controlSize(.small)
                            }
                        }
                        if let usage = row.usage, usage.isMeaningful {
                            DSUsageBar(fraction: usage.fraction)
                        }
                    }
                    .padding(.vertical, .space4)
                }
            } header: {
                sectionHeader(L10n.Settings.sectionServerStorage)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private func usageCaption(_ usage: StorageUsage) -> String {
        L10n.Settings.serverStorageUsed(
            Self.byteFormatter.string(fromByteCount: usage.used),
            Self.byteFormatter.string(fromByteCount: usage.capacity)
        )
    }

    @ViewBuilder
    private var profileSection: some View {
        Section {
            HStack(spacing: Constants.profileRowSpacing) {
                AvatarView(displayName: store.displayName, size: Constants.avatarSize)

                VStack(alignment: .leading, spacing: .space2) {
                    Text(store.displayName).type(.body2(.bold), style: .primary(for: .label))
                    if let email = store.user.email {
                        Text(email).type(.body3(.regular), style: .secondary).lineLimit(1).truncationMode(.tail)
                    }
                }

                Spacer()
            }
            .overlay(alignment: .topTrailing) {
                if store.user.isAdmin {
                    roleTag
                }
            }
            .listRowSeparator(.hidden, edges: .bottom)

            serverRow
                .listRowSeparator(.hidden, edges: .top)

            changePasswordRow
            signOutRow
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// The server the session is bound to: its branding logo + name, host beneath. Admins can
    /// tap through to `ServerDetailsView` to edit the branding; for everyone else it's a plain
    /// read-only row.
    @ViewBuilder
    private var serverRow: some View {
        let content = HStack(spacing: Constants.rowIconSpacing) {
            ServerLogoThumbnail(
                branding: store.branding,
                serverURL: store.serverURL,
                size: Constants.serverLogoSize
            )
            VStack(alignment: .leading, spacing: .space2) {
                Text(store.branding.appName).type(.body2(.regular), style: .primary(for: .label))
                if let host = store.serverURL.host {
                    Text(host).type(.body3(.regular), style: .secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if store.user.isAdmin {
                IconKit.chevronRight
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.tertiaryDS)
                    .frame(width: .iconXSmall, height: .iconXSmall)
            }
        }
        .contentShape(Rectangle())

        if store.user.isAdmin {
            Button { store.send(.serverDetailsButtonTapped) } label: { content }
                .buttonStyle(DSHapticButtonStyle())
                .disabled(store.isSigningOut)
        } else {
            content
        }
    }

    /// Self service password change (`POST /api/auth/password`). No profile editing here: the
    /// backend has no self service profile endpoint, so an admin changes that from User
    /// Management instead.
    private var changePasswordRow: some View {
        DSNavigationRow(title: L10n.Settings.rowChangePassword, icon: IconKit.key) {
            store.send(.changePasswordButtonTapped)
        }
        .disabled(store.isSigningOut)
    }

    /// Full width row, leading aligned like the rest of the card, in error red.
    private var signOutRow: some View {
        DSNavigationRow(
            title: store.isSigningOut ? L10n.Settings.signingOut : L10n.Settings.signOutButton,
            icon: IconKit.signOut,
            accessory: .none,
            role: .destructive,
            isLoading: store.isSigningOut
        ) {
            store.send(.signOutButtonTapped)
        }
        .animation(.easeInOut(duration: Constants.signOutFadeDuration), value: store.isSigningOut)
    }

    private var roleTag: some View {
        Text(L10n.Settings.sectionAdmin.uppercased())
            .type(.caption(.semibold), style: .link)
            .padding(.horizontal, Constants.tagHorizontalPadding)
            .padding(.vertical, Constants.tagVerticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: .radiusSmall, ).strokeBorder(Color.accent, lineWidth: Constants.tagBorderWidth)
            )
    }
}

@MainActor
private func settingsPreview(
    configureClient: @Sendable (inout FilesClient) -> Void = { _ in }
) -> some View {
    let state = SettingsFeature.State(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [UserRole.admin])
    )
    var client = FilesClient.previewValue
    configureClient(&client)
    return SettingsView(
        store: Store(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient = client
        }
    )
}

/// The default `.previewValue` reports `volumeUsage` enabled with two volumes, so the
/// server-storage section fills in from `onAppear` like the real thing.
#Preview {
    settingsPreview()
}

#Preview("Server storage — off") {
    settingsPreview {
        $0.serverFeatures = { _ in ServerFeatures(isVolumeUsageEnabled: false) }
    }
}

#Preview("Server storage — loading") {
    settingsPreview {
        $0.fetchUsage = { _, _ in
            try? await Task.sleep(for: .seconds(30))
            return StorageUsage()
        }
    }
}

#Preview("Server storage — filling up") {
    settingsPreview {
        $0.fetchUsage = { _, path in
            StorageUsage(path: path, size: 78_000_000_000, free: 22_000_000_000, total: 100_000_000_000)
        }
    }
}

#Preview("Server storage — nearly full") {
    settingsPreview {
        $0.fetchUsage = { _, path in
            StorageUsage(path: path, size: 96_000_000_000, free: 4_000_000_000, total: 100_000_000_000)
        }
    }
}
