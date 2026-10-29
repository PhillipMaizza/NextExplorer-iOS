import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Metrics {
    /// Settings rows are sparser than file rows, so on macOS they get a little more height.
    static let macRowVerticalPadding: CGFloat = .space16
    /// Room under the version footer so the last rows clear the floating tab bar comfortably.
    static let listBottomPadding: CGFloat = .space48
}

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    /// One toast host for the whole Settings navigation stack. User Management raises success
    /// messages from two levels down (the list and the pushed user detail); hosting the toast
    /// here, above every `.navigationDestination`, is the only spot a bottom overlay isn't
    /// occluded by a pushed screen, so those two views don't each need their own.
    @State private var userManagementToast: DSToastMessage?
    @State private var tipToast: DSToastMessage?
    /// View-local filter for the settings list — no reducer state needed, it only hides rows.
    @State private var settingsSearch = ""

    private var filter: SettingsSearchFilter {
        SettingsSearchFilter(query: settingsSearch)
    }

    @Environment(\.isSplitViewDetail) private var isSplitViewDetail

    /// Top padding for the pinned title, so it lines up with the other tabs. Those carry a
    /// toolbar button that reserves nav bar height; Settings has none, so it pads to match.
    /// `.size44` aligns on iOS 18 through 25; iOS 26's taller glass nav bar reserves ~10pt more,
    /// measured against the Downloads tab title. On iPad (the split view detail) there's no such
    /// reserved nav bar, so the padding is just dead space above the title.
    private var titleTopPadding: CGFloat {
        if isSplitViewDetail {
            return 0
        }
        if #available(iOS 26.0, macOS 26.0, *) {
            return .size44 + .space8 + .space2
        }
        return .size44
    }

    // No op setters: each confirmation sheet is dismiss disabled and only closes through one
    // of `DSAlertSheet`'s own buttons, which drive the reducer directly.

    private var isConfirmingRemoveAllDownloads: Binding<Bool> {
        Binding(get: { store.removeAllDownloadsConfirmationIsPresented }, set: { _ in })
    }

    private var isConfirmingClearCache: Binding<Bool> {
        Binding(get: { store.clearCacheConfirmationIsPresented }, set: { _ in })
    }

    private var isConfirmingRemoveOffline: Binding<Bool> {
        Binding(get: { store.removeOfflineConfirmationIsPresented }, set: { _ in })
    }

    /// The Mac shows Change Password as a window sheet (`AccountConfirmations`), opened from the
    /// sidebar's account popover, so Settings never pushes it there.
    private var changePasswordDestination: Binding<StoreOf<ChangePasswordFeature>?> {
        AccountConfirmations.isHostedByWindow ? .constant(nil) : $store.scope(state: \.changePassword, action: \.changePassword)
    }

    var body: some View {
        root
            .tint(Color.accent)
            .dsToast(userManagementToastBinding)
            .dsToast(tipToastBinding)
            .onChange(of: store.userManagement?.toast) { _, toast in
                guard let toast else { return }
                userManagementToast = .success(toast)
            }
            .onChange(of: store.tipToast) { _, message in
                guard let message else { return }
                tipToast = .success(message)
                store.send(.tipToastShown)
            }
    }

    private var root: some View {
        #if os(macOS)
            // The Mac's Settings window: native toolbar tabs, each its own navigation stack.
            windowChrome(TabView {
                macTab(L10n.Settings.sectionGeneral, icon: IconKit.gearshape) {
                    serverDetailsDestination(settingsList {
                        SettingsProfileSection(store: store)
                        GeneralSettingsSection(store: store, filter: filter)
                        DisplaySettingsSection(store: store, filter: filter)
                    })
                }
                macTab(L10n.Settings.sectionStorage, icon: IconKit.size) {
                    offlineDestination(settingsList {
                        StorageSettingsSection(store: store, filter: filter)
                        OfflineSettingsSection(store: store, filter: filter)
                    })
                }
                if store.user.isAdmin {
                    macTab(L10n.Settings.sectionAdmin, icon: IconKit.people) {
                        adminDestinations(settingsList {
                            SettingsUsersSection(store: store)
                            SettingsServerAdminSection(store: store)
                            SettingsServerStorageSection(store: store)
                        })
                    }
                }
                macTab(L10n.Settings.sectionInfo, icon: IconKit.info) {
                    settingsList {
                        SupportSettingsSection(filter: filter)
                        LegalSettingsSection(filter: filter)
                        LicensesSettingsSection(store: store, filter: filter)
                    }
                }
            })
        #else
            NavigationStack {
                windowChrome(
                    adminDestinations(offlineDestination(serverDetailsDestination(changePasswordDestinationView(
                        settingsList {
                            if !filter.isActive {
                                SettingsAccountsSection(store: store)
                                SettingsProfileSection(store: store)
                            }

                            GeneralSettingsSection(store: store, filter: filter)
                            DisplaySettingsSection(store: store, filter: filter)

                            if !filter.isActive {
                                SettingsUsersSection(store: store)
                                SettingsServerAdminSection(store: store)
                                SettingsServerStorageSection(store: store)
                            }

                            StorageSettingsSection(store: store, filter: filter)
                            OfflineSettingsSection(store: store, filter: filter)
                            SupportSettingsSection(filter: filter)
                            LegalSettingsSection(filter: filter)
                            LicensesSettingsSection(store: store, filter: filter)
                        }
                    ))))
                )
            }
        #endif
    }

    /// The grouped list every Settings page shares, with its title.
    private func settingsList(@ViewBuilder _ sections: () -> some View) -> some View {
        DSGroupedList {
            sections()
        }
        .groupedListRowVerticalPadding(Metrics.macRowVerticalPadding)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, Metrics.listBottomPadding, for: .scrollContent)
        .backgroundGradient()
        .dismissKeyboardOnTap()
        #if os(iOS)
            .safeAreaInset(edge: .top, spacing: 0) {
                PinnedTitleSearchHeader(
                    title: L10n.Settings.navigationTitle,
                    searchText: $settingsSearch,
                    extraTopPadding: titleTopPadding,
                    showsSearchField: false
                )
            }
            // Title lives in the pinned header (see `PinnedTitleSearchHeader`).
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        #else
            // The Settings window names itself; it has no pinned header.
            .navigationTitle(L10n.Settings.navigationTitle)
        #endif
    }

    #if os(macOS)
        private func macTab(_ title: String, icon: Image, @ViewBuilder content: () -> some View) -> some View {
            NavigationStack { content() }
                .tabItem { Label { Text(title) } icon: { icon } }
        }
    #endif

    private func serverDetailsDestination(_ content: some View) -> some View {
        content.navigationDestination(item: $store.scope(state: \.serverDetails, action: \.serverDetails)) { serverDetailsStore in
            ServerDetailsView(store: serverDetailsStore)
        }
    }

    private func changePasswordDestinationView(_ content: some View) -> some View {
        content.navigationDestination(item: changePasswordDestination) { changePasswordStore in
            ChangePasswordView(store: changePasswordStore)
        }
    }

    private func offlineDestination(_ content: some View) -> some View {
        content.navigationDestination(item: $store.scope(state: \.offlineManage, action: \.offlineManage)) { manageStore in
            OfflineManageView(store: manageStore)
        }
    }

    private func adminDestinations(_ content: some View) -> some View {
        content
            .navigationDestination(item: $store.scope(state: \.userManagement, action: \.userManagement)) { userManagementStore in
                UserManagementView(store: userManagementStore)
            }
            .navigationDestination(item: $store.scope(state: \.thumbnailSettings, action: \.thumbnailSettings)) { thumbnailStore in
                ThumbnailSettingsView(store: thumbnailStore)
            }
            .navigationDestination(item: $store.scope(state: \.accessRules, action: \.accessRules)) { accessRulesStore in
                AccessRulesView(store: accessRulesStore)
            }
    }

    /// Confirmations, sheets and the load task, attached once around the whole Settings UI.
    private func windowChrome(_ content: some View) -> some View {
        content
            // The Mac hosts these at the window level instead, for its sidebar account menu.
            .modifier(AccountConfirmations(store: store, isEnabled: !AccountConfirmations.isHostedByWindow))
            .dsAlert(isPresented: isConfirmingRemoveAllDownloads) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.Settings.removeAllDownloadsTitle,
                    message: L10n.Settings.removeAllDownloadsMessage,
                    confirmTitle: L10n.Settings.removeAllDownloadsConfirm,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.removeAllDownloadsConfirmed) },
                    onDismiss: { store.send(.removeAllDownloadsCancelled) }
                )
            }
            .hapticFeedback(.warning, trigger: store.removeAllDownloadsConfirmationIsPresented)
            .dsAlert(isPresented: isConfirmingClearCache) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.Settings.clearCacheTitle,
                    message: L10n.Settings.clearCacheMessage,
                    confirmTitle: L10n.Settings.clearCacheConfirm,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.clearCacheConfirmed) },
                    onDismiss: { store.send(.clearCacheCancelled) }
                )
            }
            .hapticFeedback(.warning, trigger: store.clearCacheConfirmationIsPresented)
            .dsSheet(item: $store.scope(state: \.tipJar, action: \.tipJar)) { tipStore in
                TipJarSheet(store: tipStore) { store.send(.tipJar(.dismiss)) }
            }
            .sheet(item: $store.scope(state: \.offlineSelection, action: \.offlineSelection)) { selectionStore in
                OfflineSelectionView(store: selectionStore)
            }
            .dsAlert(isPresented: isConfirmingRemoveOffline) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.Offline.removeConfirmTitle,
                    message: L10n.Offline.removeConfirmMessage,
                    confirmTitle: L10n.Offline.removeConfirm,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.removeOfflineConfirmed) },
                    onDismiss: { store.send(.removeOfflineCancelled) }
                )
            }
            .hapticFeedback(.warning, trigger: store.removeOfflineConfirmationIsPresented)
            .task {
                store.send(.onAppear)
            }
            .onChange(of: store.offlineProgress.phase) { _, phase in
                if phase == .completed {
                    store.send(.refreshOfflineSize)
                }
            }
    }

    private var tipToastBinding: Binding<DSToastMessage?> {
        Binding(get: { tipToast }, set: { tipToast = $0 })
    }

    private var userManagementToastBinding: Binding<DSToastMessage?> {
        Binding(
            get: { userManagementToast },
            set: { newValue in
                userManagementToast = newValue
                if newValue == nil {
                    store.send(.userManagement(.presented(.toastDismissed)))
                }
            }
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

// The default `.previewValue` reports `volumeUsage` enabled with two volumes, so the
// server-storage section fills in from `onAppear` like the real thing.
#Preview {
    settingsPreview()
}

#Preview("Accounts — multiple") {
    @Shared(.inMemory(AccountSummary.sharedKey)) var accounts: [AccountSummary] = []
    $accounts.withLock {
        $0 = [
            AccountSummary(id: "a", username: "jdoe", serverURL: URL(string: "https://home.example.com") ?? URL(fileURLWithPath: "/"), isActive: true),
            AccountSummary(id: "b", username: "work", serverURL: URL(string: "https://files.acme.example.net") ?? URL(fileURLWithPath: "/"), isActive: false),
        ]
    }
    return settingsPreview()
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
