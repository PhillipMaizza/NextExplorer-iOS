#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let sidebarWidth: CGFloat = 272
    }

    struct MacSettingsShell<Sidebar: View, Detail: View>: View {
        @ViewBuilder let sidebar: () -> Sidebar
        @ViewBuilder let detail: () -> Detail

        var body: some View {
            HStack(spacing: .zero) {
                List(content: sidebar)
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .clipped()
                    .frame(width: Metrics.sidebarWidth)
                detail()
            }
            .containerBackground(Color.macChrome, for: .window)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
        }
    }

    /// One page of the Mac Settings window's sidebar.
    enum MacSettingsCategory: String, CaseIterable, Identifiable {
        case accounts
        case general
        case storage
        case apiTokens
        case server
        case users
        case thumbnails
        case accessRules
        case uploads
        case searchIndex
        case folderSize
        case ffmpeg
        case activity
        case serverTools
        case trash
        case versions
        case about

        var id: String {
            rawValue
        }

        var adminPane: SettingsFeature.AdminPane? {
            switch self {
            case .server: .server
            case .users: .users
            case .thumbnails: .thumbnails
            case .accessRules: .accessRules
            case .uploads: .uploads
            case .searchIndex: .searchIndex
            case .folderSize: .folderSize
            case .ffmpeg: .ffmpeg
            case .activity: .activity
            case .serverTools: .serverTools
            case .trash: .trash
            case .versions: .versions
            case .accounts, .general, .storage, .apiTokens, .about: nil
            }
        }

        static let everyone: [Self] = [.accounts, .general, .storage, .apiTokens]
        static let admin: [Self] = [
            .server,
            .users,
            .thumbnails,
            .accessRules,
            .uploads,
            .searchIndex,
            .folderSize,
            .ffmpeg,
            .trash,
            .versions,
            .activity,
            .serverTools,
        ]
        static let app: [Self] = [.about]

        var headerTitle: String? {
            self == .about ? nil : title
        }

        var subtitle: String? {
            switch self {
            case .thumbnails: L10n.ThumbnailSettings.subtitle
            case .accessRules: L10n.AccessRules.subtitle
            case .uploads: L10n.UploadSettings.subtitle
            case .searchIndex: L10n.SearchIndexSettings.subtitle
            case .folderSize: L10n.FolderSizeSettings.subtitle
            case .ffmpeg: L10n.FfmpegSettings.subtitle
            case .activity: L10n.ActivityLog.subtitle
            case .serverTools: L10n.ServerTools.subtitle
            case .accounts, .general, .storage, .apiTokens, .server, .users, .trash, .versions, .about: nil
            }
        }

        var title: String {
            switch self {
            case .accounts: L10n.Settings.sectionAccounts
            case .general: L10n.Settings.sectionGeneral
            case .storage: L10n.Settings.sectionStorage
            case .apiTokens: L10n.ApiTokens.navigationTitle
            case .server: L10n.Settings.rowServer
            case .users: L10n.Settings.rowUserManagement
            case .thumbnails: L10n.Settings.rowThumbnails
            case .accessRules: L10n.Settings.rowAccessRules
            case .uploads: L10n.UploadSettings.navigationTitle
            case .searchIndex: L10n.SearchIndexSettings.navigationTitle
            case .folderSize: L10n.FolderSizeSettings.navigationTitle
            case .ffmpeg: L10n.FfmpegSettings.navigationTitle
            case .activity: L10n.ActivityLog.navigationTitle
            case .serverTools: L10n.ServerTools.navigationTitle
            case .trash: L10n.TrashSettings.navigationTitle
            case .versions: L10n.VersionedFiles.navigationTitle
            case .about: L10n.Settings.sectionInfo
            }
        }

        var icon: Image {
            switch self {
            case .accounts: IconKit.account
            case .general: IconKit.gearshape
            case .storage: IconKit.storage
            case .apiTokens: IconKit.key
            case .server: IconKit.serverRack
            case .users: IconKit.people
            case .thumbnails: IconKit.photo
            case .accessRules: IconKit.accessRules
            case .uploads: IconKit.upload
            case .searchIndex: IconKit.search
            case .folderSize: IconKit.folder
            case .ffmpeg: IconKit.film
            case .activity: IconKit.time
            case .serverTools: IconKit.gearshape
            case .trash: IconKit.delete
            case .versions: IconKit.archiveDocument
            case .about: IconKit.info
            }
        }
    }

    /// The Mac Settings window, laid out like Xcode's and System Settings': a sidebar of
    /// categories, each opening its own pane. The admin pages follow as their own group, then
    /// the app's own info.
    struct MacSettingsRoot: View {
        @Bindable var store: StoreOf<SettingsFeature>
        @AppStorage(AppStorageKeys.macSettingsPane) private var selection: MacSettingsCategory = .general
        @State private var isShowingLicenses = false
        @State private var ownerAccountID: String?
        @State private var pendingSelection: MacSettingsCategory?

        private var visibleSelection: MacSettingsCategory {
            store.user.isAdmin || !MacSettingsCategory.admin.contains(selection) ? selection : .general
        }

        private func subtitle(for category: MacSettingsCategory) -> String? {
            guard category == .trash else { return category.subtitle }
            return store.trashSettings?.latestMaintenanceZone
                .map { L10n.TrashSettings.lastPass(TrashSettingsView.lastPass(for: $0)) }
        }

        var body: some View {
            MacSettingsShell {
                Section {
                    ForEach(MacSettingsCategory.everyone) { sidebarRow($0) }
                }
                if store.user.isAdmin {
                    Section(L10n.Settings.sectionAdmin) {
                        ForEach(MacSettingsCategory.admin) { sidebarRow($0) }
                    }
                }
                Section {
                    ForEach(MacSettingsCategory.app) { sidebarRow($0) }
                }
            } detail: {
                NavigationStack {
                    MacPaneCard(title: visibleSelection.headerTitle, subtitle: subtitle(for: visibleSelection)) {
                        pane(visibleSelection)
                    } tools: {
                        MacSettingsHeaderTools(store: store, category: visibleSelection)
                    }
                    .navigationTitle(visibleSelection.title)
                    .toolbar(removing: .title)
                    .navigationDestination(item: $store.scope(
                        state: \.offlineManage,
                        action: \.offlineManage
                    )) { manageStore in
                        MacOfflineManagePane(store: manageStore)
                    }
                }
                .id(visibleSelection)
            }
            // A pane left behind (another category, or the window closed) is released, so coming
            // back loads it fresh: the Users list otherwise kept showing what it first loaded.
            .onChange(of: visibleSelection) { previous, _ in release(previous) }
            .onAppear { ownerAccountID = store.accountID }
            .onDisappear {
                guard store.accountID == ownerAccountID,
                      !(visibleSelection.adminPane.map(store.state.hasUnsavedChanges(in:)) ?? false) else { return }
                release(visibleSelection)
            }
            .macLicensesSheet(isPresented: $isShowingLicenses)
            .alert(
                L10n.EditShare.discardTitle,
                isPresented: Binding(get: { pendingSelection != nil }, set: {
                    if !$0 {
                        pendingSelection = nil
                    }
                }),
                presenting: pendingSelection
            ) { category in
                Button(L10n.EditShare.discard, role: .destructive) {
                    pendingSelection = nil
                    selection = category
                }
                Button(L10n.EditShare.keepEditing, role: .cancel) { pendingSelection = nil }
            } message: { _ in
                Text(L10n.TextPreview.unsavedMessage)
            }
        }

        private func release(_ category: MacSettingsCategory) {
            if let pane = category.adminPane {
                store.send(.adminPaneLeft(pane))
            } else if category == .apiTokens, store.apiTokens != nil {
                store.send(.apiTokens(.dismiss))
            }
        }

        private func select(_ category: MacSettingsCategory) {
            guard category != visibleSelection else { return }
            if let pane = visibleSelection.adminPane, store.state.hasUnsavedChanges(in: pane) {
                pendingSelection = category
            } else {
                selection = category
            }
        }

        private func sidebarRow(_ category: MacSettingsCategory) -> some View {
            MacSidebarRow(
                title: category.title,
                icon: category.icon,
                isSelected: category == visibleSelection
            ) {
                select(category)
            }
            .macSettingsSidebarRow()
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
            case .apiTokens:
                if let tokensStore = store.scope(state: \.apiTokens, action: \.apiTokens.presented) {
                    MacAPITokensPane(store: tokensStore)
                } else {
                    Color.clear.onAppear { store.send(.apiTokensButtonTapped) }
                }
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
                MacSettingsInfoPane(
                    onTip: { store.send(.tipJarButtonTapped) },
                    onLicenses: { isShowingLicenses = true }
                )
            case .accessRules:
                if let detailStore = store.scope(state: \.accessRules, action: \.accessRules.presented) {
                    MacAccessRulesPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.accessRulesButtonTapped) }
                }
            case .uploads:
                if let detailStore = store.scope(state: \.uploadSettings, action: \.uploadSettings.presented) {
                    MacUploadSettingsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.uploadSettingsButtonTapped) }
                }
            case .searchIndex:
                if let detailStore = store
                    .scope(state: \.searchIndexSettings, action: \.searchIndexSettings.presented)
                {
                    MacSearchIndexSettingsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.searchIndexSettingsButtonTapped) }
                }
            case .folderSize:
                if let detailStore = store.scope(state: \.folderSizeSettings, action: \.folderSizeSettings.presented) {
                    MacFolderSizeSettingsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.folderSizeSettingsButtonTapped) }
                }
            case .ffmpeg:
                if let detailStore = store.scope(state: \.ffmpegSettings, action: \.ffmpegSettings.presented) {
                    MacFFmpegSettingsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.ffmpegSettingsButtonTapped) }
                }
            case .activity:
                if let detailStore = store.scope(state: \.activityLog, action: \.activityLog.presented) {
                    MacActivityLogPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.activityLogButtonTapped) }
                }
            case .serverTools:
                if let detailStore = store.scope(state: \.serverTools, action: \.serverTools.presented) {
                    MacServerToolsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.serverToolsButtonTapped) }
                }
            case .trash:
                if let detailStore = store.scope(state: \.trashSettings, action: \.trashSettings.presented) {
                    MacTrashSettingsPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.trashSettingsButtonTapped) }
                }
            case .versions:
                if let detailStore = store.scope(state: \.versionedFiles, action: \.versionedFiles.presented) {
                    MacVersionedFilesPane(store: detailStore)
                } else {
                    Color.clear.onAppear { store.send(.versionedFilesButtonTapped) }
                }
            }
        }
    }

    #Preview("Settings window") {
        MacSettingsRoot(store: Store(initialState: .macPreview) { SettingsFeature() })
            .previewCanvas(.settingsWindow)
    }
#endif
