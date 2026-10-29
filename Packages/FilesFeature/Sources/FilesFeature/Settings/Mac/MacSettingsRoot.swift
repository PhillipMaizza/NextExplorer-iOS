#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let sidebarWidth: CGFloat = 200
        static let iconSize: CGFloat = 22
        static let iconGlyphSize: CGFloat = 12
        static let iconCornerRadius: CGFloat = 5
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

        var id: String {
            rawValue
        }

        static let everyone: [Self] = [.accounts, .general, .storage]
        static let admin: [Self] = [.server, .users, .thumbnails, .accessRules]

        var title: String {
            switch self {
            case .accounts: L10n.Settings.sectionAccounts
            case .general: L10n.Settings.sectionGeneral
            case .storage: L10n.Settings.sectionStorage
            case .server: L10n.Settings.rowServer
            case .users: L10n.Settings.sectionUsers
            case .thumbnails: L10n.Settings.rowThumbnails
            case .accessRules: L10n.Settings.rowAccessRules
            }
        }

        var systemImage: String {
            switch self {
            case .accounts: "person.crop.circle.fill"
            case .general: "gearshape.fill"
            case .storage: "internaldrive.fill"
            case .server: "server.rack"
            case .users: "person.2.fill"
            case .thumbnails: "photo.fill"
            case .accessRules: "lock.shield.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .accounts: .blue
            case .general: .gray
            case .storage: .gray
            case .server: .indigo
            case .users: .blue
            case .thumbnails: .orange
            case .accessRules: .green
            }
        }
    }

    /// The Mac Settings window, laid out like Xcode's and System Settings': a sidebar of
    /// categories, each opening its own pane. The admin pages follow under their own heading.
    struct MacSettingsRoot: View {
        @Bindable var store: StoreOf<SettingsFeature>
        @SceneStorage("macSettingsCategory") private var selection: MacSettingsCategory = .general

        private var visibleSelection: MacSettingsCategory {
            store.user.isAdmin || MacSettingsCategory.everyone.contains(selection) ? selection : .general
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
                        Section(L10n.Settings.sectionAdmin) {
                            ForEach(MacSettingsCategory.admin) { sidebarRow($0) }
                        }
                    }
                }
                .navigationSplitViewColumnWidth(Metrics.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                NavigationStack {
                    pane(visibleSelection)
                        .navigationTitle(visibleSelection.title)
                        .navigationDestination(item: $store.scope(state: \.offlineManage, action: \.offlineManage)) { manageStore in
                            OfflineManageView(store: manageStore)
                        }
                }
                .id(visibleSelection)
            }
        }

        private func sidebarRow(_ category: MacSettingsCategory) -> some View {
            Label {
                Text(category.title)
            } icon: {
                Image(systemName: category.systemImage)
                    .font(.system(size: Metrics.iconGlyphSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                    .background(category.iconColor.gradient, in: RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous))
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
                    ServerDetailsView(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.serverDetailsButtonTapped) }
                }
            case .users:
                if let detailStore = store.scope(state: \.userManagement, action: \.userManagement.presented) {
                    UserManagementView(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.userManagementButtonTapped) }
                }
            case .thumbnails:
                if let detailStore = store.scope(state: \.thumbnailSettings, action: \.thumbnailSettings.presented) {
                    ThumbnailSettingsView(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.thumbnailSettingsButtonTapped) }
                }
            case .accessRules:
                if let detailStore = store.scope(state: \.accessRules, action: \.accessRules.presented) {
                    AccessRulesView(store: detailStore)
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
