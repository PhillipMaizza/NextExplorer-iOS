#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let sidebarWidth: CGFloat = 200
    }

    /// One page of the Mac Settings window's sidebar.
    enum MacSettingsCategory: String, CaseIterable, Identifiable {
        case accounts
        case general
        case storage
        case server
        case users
        case thumbnails
        case accessRules
        case about

        var id: String {
            rawValue
        }

        static let everyone: [Self] = [.accounts, .general, .storage]
        static let admin: [Self] = [.server, .users, .thumbnails, .accessRules]
        static let app: [Self] = [.about]

        var title: String {
            switch self {
            case .accounts: L10n.Settings.sectionAccounts
            case .general: L10n.Settings.sectionGeneral
            case .storage: L10n.Settings.sectionStorage
            case .server: L10n.Settings.rowServer
            case .users: L10n.Settings.sectionUsers
            case .thumbnails: L10n.Settings.rowThumbnails
            case .accessRules: L10n.Settings.rowAccessRules
            case .about: L10n.Settings.sectionInfo
            }
        }

        var icon: Image {
            switch self {
            case .accounts: IconKit.account
            case .general: IconKit.gearshape
            case .storage: IconKit.storage
            case .server: IconKit.serverRack
            case .users: IconKit.people
            case .thumbnails: IconKit.photo
            case .accessRules: IconKit.accessRules
            case .about: IconKit.info
            }
        }
    }

    /// The Mac Settings window, laid out like Xcode's and System Settings': a sidebar of
    /// categories, each opening its own pane. The admin pages follow as their own group, then
    /// the app's own info.
    struct MacSettingsRoot: View {
        @Bindable var store: StoreOf<SettingsFeature>
        @SceneStorage("macSettingsCategory") private var selection: MacSettingsCategory = .general

        private var visibleSelection: MacSettingsCategory {
            store.user.isAdmin || !MacSettingsCategory.admin.contains(selection) ? selection : .general
        }

        var body: some View {
            NavigationSplitView {
                List(selection: Binding(get: { visibleSelection }, set: {
                    if let category = $0 {
                        selection = category
                    }
                })) {
                    Section {
                        ForEach(MacSettingsCategory.everyone) { sidebarRow($0) }
                    }
                    if store.user.isAdmin {
                        Section {
                            ForEach(MacSettingsCategory.admin) { sidebarRow($0) }
                        }
                    }
                    Section {
                        ForEach(MacSettingsCategory.app) { sidebarRow($0) }
                    }
                }
                .navigationSplitViewColumnWidth(Metrics.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                NavigationStack {
                    pane(visibleSelection)
                        .navigationTitle(visibleSelection.title)
                        .navigationDestination(item: $store.scope(state: \.offlineManage, action: \.offlineManage)) { manageStore in
                            MacOfflineManagePane(store: manageStore)
                        }
                }
                .id(visibleSelection)
            }
        }

        /// Xcode style: an outline glyph in the app accent, white on the selected row.
        private func sidebarRow(_ category: MacSettingsCategory) -> some View {
            Label {
                Text(category.title)
            } icon: {
                category.icon
                    .foregroundStyle(category == visibleSelection ? Color.white : Color.accent)
            }
            .tag(category)
        }

        @ViewBuilder
        private func pane(_ category: MacSettingsCategory) -> some View {
            switch category {
            case .accounts:
                MacAccountsSettingsTab(store: store)
            case .general:
                MacGeneralSettingsTab(store: store)
            case .storage:
                MacStorageSettingsTab(store: store)
            case .server:
                if let detailStore = store.scope(state: \.serverDetails, action: \.serverDetails.presented) {
                    MacServerSettingsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.serverDetailsButtonTapped) }
                }
            case .users:
                if let detailStore = store.scope(state: \.userManagement, action: \.userManagement.presented) {
                    MacUsersSettingsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.userManagementButtonTapped) }
                }
            case .thumbnails:
                if let detailStore = store.scope(state: \.thumbnailSettings, action: \.thumbnailSettings.presented) {
                    MacThumbnailSettingsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.thumbnailSettingsButtonTapped) }
                }
            case .about:
                MacAboutContent { store.send(.tipJarButtonTapped) }
                    .padding(.space32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .accessRules:
                if let detailStore = store.scope(state: \.accessRules, action: \.accessRules.presented) {
                    MacAccessRulesPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.accessRulesButtonTapped) }
                }
            }
        }
    }

    #Preview("Settings window") {
        MacSettingsRoot(store: Store(initialState: .macPreview) { SettingsFeature() })
            .frame(width: 760, height: 520)
    }
#endif
