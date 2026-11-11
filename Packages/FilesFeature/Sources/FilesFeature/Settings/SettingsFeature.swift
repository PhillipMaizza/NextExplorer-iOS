import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient

/// Account info, the two `user_settings` preferences that affect anything this app has
/// built (`showHiddenFiles`, `showThumbnails`, see `UserPreferences`), and sign out.
/// The sign-out network call itself is owned by the parent (`AuthenticatedFeature`,
/// which already holds `authClient`); this only surfaces the confirmed tap and
/// displays whatever `isSigningOut` the parent drives back down.
@Reducer
public struct SettingsFeature {
    /// Whether the account can use the password rows: a single sign on account has no password
    /// until it adds one.
    public enum PasswordStatus: Equatable, Sendable {
        case unknown
        case present
        case absent
    }

    /// Whether the server lets accounts sign in with a password, from `GET /api/auth/status`.
    public enum LocalSignInStatus: Equatable, Sendable {
        case unknown
        case enabled
        case disabled
    }

    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var user: User
        public var isSigningOut = false
        public var isConfirmingSignOut = false
        /// Whether the account has a password, from `GET /api/auth/methods`. `unknown` until the
        /// answer arrives and when it can't be fetched, which keeps today's Change Password row.
        public var passwordStatus: PasswordStatus = .unknown
        /// `unknown` until the answer arrives and when it can't be fetched, which keeps the rows.
        public var localSignInStatus: LocalSignInStatus = .unknown

        /// A password does nothing on a server that has password sign in off (`AUTH_MODE=oidc`).
        public var showsPasswordRow: Bool {
            localSignInStatus != .disabled
        }

        /// The second factor guards the password sign in, so it needs both the server to allow
        /// that sign in and the account to have a password. The web app hides it the same way.
        public var showsTwoFactorRow: Bool {
            showsPasswordRow && passwordStatus != .absent
        }

        /// Held by the feature, not created inline in the view: a `Store` built in a
        /// `NavigationLink`'s destination builder is torn down and rebuilt empty on any
        /// parent re render, such as returning from the background, which is what left the
        /// user list blank.
        @Presents public var userManagement: UserManagementFeature.State?
        @Presents public var changePassword: ChangePasswordFeature.State?
        @Presents public var twoFactor: TwoFactorFeature.State?
        @Presents public var apiTokens: APITokensFeature.State?
        @Presents public var serverDetails: ServerDetailsFeature.State?
        @Presents public var thumbnailSettings: ThumbnailSettingsFeature.State?
        @Presents public var uploadSettings: UploadSettingsFeature.State?
        @Presents public var ffmpegSettings: FFmpegSettingsFeature.State?
        @Presents public var searchIndexSettings: SearchIndexSettingsFeature.State?
        @Presents public var folderSizeSettings: FolderSizeSettingsFeature.State?
        @Presents public var activityLog: ActivityLogFeature.State?
        @Presents public var trashSettings: TrashSettingsFeature.State?
        @Presents public var versionedFiles: VersionedFilesFeature.State?
        @Presents public var accessRules: AccessRulesFeature.State?
        @Presents public var offlineSelection: OfflineSelectionFeature.State?
        @Presents public var offlineManage: OfflineManageFeature.State?
        @Presents public var tipJar: TipJarFeature.State?
        @Presents public var clientCertificate: ClientCertificateFeature.State?
        /// The client certificate presented to this account's server, shown on its Settings row.
        public var clientCertificateStatus: ClientCertificateFeature.Status = .loading
        /// Where files shared from other apps go for this account.
        public var uploadDefaults: UploadDefaultsFeature.State
        /// One shot signal: set when a tip completes so the view can raise the thank you toast,
        /// cleared by `tipToastShown`.
        public var tipToast: String?
        /// Server branding, fetched on appear and shared with `ServerDetailsFeature` so an
        /// admin's edit there is reflected in the server row the moment it saves.
        @Shared(.inMemory(Branding.sharedKey)) public var branding = Branding()
        /// Shared with `BrowseFeature` under the same in-memory key, so toggling
        /// "Show Hidden Files" here is reflected immediately in an already-open folder.
        @Shared(.inMemory("userPreferences")) public var preferences = UserPreferences()
        /// Current account's downloads scope, so the size/existence checks count only this
        /// account's files. Shared with `BrowseFeature`/`DownloadsFeature` under one key.
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) public var downloadScope = ""
        /// Every signed-in account for the multi-server switcher, published by `AppFeature`. The
        /// actual switch / remove / add work is owned upstream (it needs `authClient`); this only
        /// renders the list and emits intent.
        @Shared(.inMemory(AccountSummary.sharedKey)) public var accounts: [AccountSummary] = []
        /// Set when the user taps to sign an account out of the switcher, driving the confirm
        /// dialog; cleared on cancel or confirm.
        public var accountPendingRemoval: AccountSummary?
        public var isLoadingPreferences = false
        public var removeAllDownloadsConfirmationIsPresented = false
        public var isRemovingAllDownloads = false
        /// Checked independently of the Downloads tab's own state (which may never have
        /// loaded, if the user hasn't visited that tab this session): this is what actually
        /// disables "Remove All Downloads" until there's proof there's nothing to remove.
        public var hasDownloads = true
        public var downloadsSize: Int64 = 0
        public var cacheSize: Int64 = 0
        public var isClearingCache = false
        public var clearCacheConfirmationIsPresented = false
        /// Durable offline store size for this account, read from `OfflineFileStore` on appear and
        /// refreshed when a download run completes.
        public var offlineSize: Int64 = 0
        public var removeOfflineConfirmationIsPresented = false
        /// Live offline download progress, published by the session lifetime engine so this screen
        /// reflects a run started here even after the user navigated away and back.
        @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) public var offlineProgress = OfflineDownloadProgress()

        /// Server disk usage, one row per volume: the iOS take on the web client's volume
        /// list. Only populated (and only shown) when `GET /api/features` reports
        /// `volumeUsage.enabled`.
        public var isVolumeUsageEnabled = false
        public var serverUsage: IdentifiedArrayOf<VolumeUsage> = []

        public var displayName: String {
            user.displayLabel
        }

        public init(serverURL: URL, user: User) {
            self.serverURL = serverURL
            self.user = user
            uploadDefaults = UploadDefaultsFeature.State(
                serverURL: serverURL,
                accountID: serverURL.absoluteString + "|" + user.username
            )
        }
    }

    public struct VolumeUsage: Equatable, Identifiable, Sendable {
        public let volume: Volume
        public var usage: StorageUsage?

        public var id: String {
            volume.path
        }
    }

    /// The admin pages the Mac Settings window shows as panes of their own.
    public enum AdminPane: Equatable, Sendable {
        case server, users, thumbnails, accessRules
        case uploads, searchIndex, folderSize, ffmpeg, activity, trash, versions
    }

    public enum Action: Sendable {
        case onAppear
        case userManagementButtonTapped
        case userManagement(PresentationAction<UserManagementFeature.Action>)
        case changePasswordButtonTapped
        case twoFactorButtonTapped
        case apiTokensButtonTapped
        case authMethodsResponse(Result<[SignInMethod], FilesClientError>)
        case authStatusResponse(Result<AuthStatus, FilesClientError>)
        case changePassword(PresentationAction<ChangePasswordFeature.Action>)
        case twoFactor(PresentationAction<TwoFactorFeature.Action>)
        case apiTokens(PresentationAction<APITokensFeature.Action>)
        case serverDetailsButtonTapped
        case serverDetails(PresentationAction<ServerDetailsFeature.Action>)
        case thumbnailSettingsButtonTapped
        case thumbnailSettings(PresentationAction<ThumbnailSettingsFeature.Action>)
        case uploadSettingsButtonTapped
        case uploadSettings(PresentationAction<UploadSettingsFeature.Action>)
        case ffmpegSettingsButtonTapped
        case ffmpegSettings(PresentationAction<FFmpegSettingsFeature.Action>)
        case searchIndexSettingsButtonTapped
        case searchIndexSettings(PresentationAction<SearchIndexSettingsFeature.Action>)
        case folderSizeSettingsButtonTapped
        case folderSizeSettings(PresentationAction<FolderSizeSettingsFeature.Action>)
        case activityLogButtonTapped
        case activityLog(PresentationAction<ActivityLogFeature.Action>)
        case trashSettingsButtonTapped
        case trashSettings(PresentationAction<TrashSettingsFeature.Action>)
        case versionedFilesButtonTapped
        case versionedFiles(PresentationAction<VersionedFilesFeature.Action>)
        case accessRulesButtonTapped
        case accessRules(PresentationAction<AccessRulesFeature.Action>)
        /// The Mac Settings window left an admin pane (another category, or the window closed):
        /// it is released so coming back loads it fresh.
        case adminPaneLeft(AdminPane)
        case offlineDownloadButtonTapped
        case offlineSelection(PresentationAction<OfflineSelectionFeature.Action>)
        case offlineManageButtonTapped
        case offlineManage(PresentationAction<OfflineManageFeature.Action>)
        case cancelOfflineDownloadTapped
        case resyncOfflineTapped
        case removeOfflineTapped
        case removeOfflineCancelled
        case removeOfflineConfirmed
        case refreshOfflineSize
        case offlineSizeResponse(Int64)
        case tipJarButtonTapped
        case tipJar(PresentationAction<TipJarFeature.Action>)
        case clientCertificateButtonTapped
        case clientCertificateStatusLoaded(ClientCertificateSummary?)
        case clientCertificate(PresentationAction<ClientCertificateFeature.Action>)
        case uploadDefaults(UploadDefaultsFeature.Action)
        case tipToastShown
        case brandingResponse(Result<Branding, FilesClientError>)
        case serverFeaturesResponse(ServerFeatures)
        case volumesResponse([Volume])
        case serverUsageResponse(path: String, Result<StorageUsage, FilesClientError>)
        case preferencesResponse(Result<UserPreferences, FilesClientError>)
        case setShowHiddenFiles(Bool)
        case setShowThumbnails(Bool)
        case updatePreferenceResponse(Result<Void, FilesClientError>)
        case signOutButtonTapped
        case cancelSignOutTapped
        case confirmSignOutTapped
        case switchAccountTapped(String)
        case addAccountTapped
        case removeAccountTapped(AccountSummary)
        case removeAccountCancelled
        case removeAccountConfirmed
        case removeAllDownloadsTapped
        case removeAllDownloadsCancelled
        case removeAllDownloadsConfirmed
        case removeAllDownloadsResponse
        case hasDownloadsResponse(Bool)
        case downloadsSizeResponse(Int64)
        case cacheSizeResponse(Int64)
        case clearCacheTapped
        case clearCacheCancelled
        case clearCacheConfirmed
        case clearCacheResponse
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case signOutButtonTapped
            /// Every local download was just deleted: `MainTabFeature` clears the
            /// Downloads tab's list without waiting for it to re-scan the (now empty) disk.
            case allDownloadsRemoved
            /// Multi-server switcher intent, handled upstream where `authClient` lives.
            case switchAccount(String)
            case removeAccount(String)
            case addAccountRequested
            /// Offline download intent, handled by the session lifetime `OfflineDownloadsFeature`
            /// engine that `MainTabFeature` owns (Settings is torn down on a tab switch; the engine
            /// is not).
            case startOfflineDownload([FileItem])
            case cancelOfflineDownload
            case resyncOffline
            case removeOfflineFiles
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.localDownloadStore) var localDownloadStore
    @Dependency(\.previewCacheStore) var previewCacheStore
    @Dependency(\.thumbnailCache) var thumbnailCache
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.jsonCacheStore) var jsonCacheStore
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.clientCertificateClient) var clientCertificateClient

    private enum CancelID: Hashable { case serverUsage, volumeUsage, preference(UserPreferenceKey), offlineSize, authMethods, authStatus }

    public init() {}

    private func core(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .userManagementButtonTapped:
            state.userManagement = UserManagementFeature.State(
                serverURL: state.serverURL,
                currentUserID: state.user.id
            )
            return .none

        case .userManagement:
            return .none

        case .changePasswordButtonTapped:
            state.changePassword = ChangePasswordFeature.State(
                serverURL: state.serverURL,
                mode: state.passwordStatus == .absent ? .add : .change
            )
            return .none

        case let .authMethodsResponse(.success(methods)):
            state.passwordStatus = methods.hasPassword ? .present : .absent
            return .none

        case .authMethodsResponse(.failure):
            return .none

        case let .authStatusResponse(.success(status)):
            state.localSignInStatus = status.isLocalEnabled ? .enabled : .disabled
            return .none

        case .authStatusResponse(.failure):
            return .none

        case .changePassword(.presented(.delegate(.passwordAdded))):
            state.passwordStatus = .present
            state.changePassword = nil
            return .none

        case .changePassword:
            return .none

        case .twoFactorButtonTapped:
            state.twoFactor = TwoFactorFeature.State(serverURL: state.serverURL)
            return .none

        case .twoFactor:
            return .none

        case .apiTokensButtonTapped:
            state.apiTokens = APITokensFeature.State(serverURL: state.serverURL, requiresPassword: state.passwordStatus != .absent)
            return .none

        case .apiTokens:
            return .none

        case .serverDetailsButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.serverDetails = ServerDetailsFeature.State(
                serverURL: state.serverURL,
                branding: state.branding
            )
            return .none

        case .serverDetails:
            return .none

        case .thumbnailSettingsButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.thumbnailSettings = ThumbnailSettingsFeature.State(serverURL: state.serverURL)
            return .none

        case .thumbnailSettings:
            return .none

        case .accessRulesButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.accessRules = AccessRulesFeature.State(serverURL: state.serverURL)
            return .none

        case .accessRules:
            return .none

        case .uploadSettingsButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.uploadSettings = UploadSettingsFeature.State(serverURL: state.serverURL)
            return .none

        case .uploadSettings:
            return .none

        case .ffmpegSettingsButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.ffmpegSettings = FFmpegSettingsFeature.State(serverURL: state.serverURL)
            return .none

        case .ffmpegSettings:
            return .none

        case .searchIndexSettingsButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.searchIndexSettings = SearchIndexSettingsFeature.State(serverURL: state.serverURL)
            return .none

        case .searchIndexSettings:
            return .none

        case .folderSizeSettingsButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.folderSizeSettings = FolderSizeSettingsFeature.State(serverURL: state.serverURL)
            return .none

        case .folderSizeSettings:
            return .none

        case .activityLogButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.activityLog = ActivityLogFeature.State(serverURL: state.serverURL)
            return .none

        case .activityLog:
            return .none

        case .trashSettingsButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.trashSettings = TrashSettingsFeature.State(serverURL: state.serverURL)
            return .none

        case .trashSettings:
            return .none

        case .versionedFilesButtonTapped:
            guard state.user.isAdmin else { return .none }
            state.versionedFiles = VersionedFilesFeature.State(serverURL: state.serverURL)
            return .none

        case .versionedFiles:
            return .none

        case let .adminPaneLeft(pane):
            switch pane {
            case .server: state.serverDetails = nil
            case .users: state.userManagement = nil
            case .thumbnails: state.thumbnailSettings = nil
            case .accessRules: state.accessRules = nil
            case .uploads: state.uploadSettings = nil
            case .searchIndex: state.searchIndexSettings = nil
            case .folderSize: state.folderSizeSettings = nil
            case .ffmpeg: state.ffmpegSettings = nil
            case .activity: state.activityLog = nil
            case .trash: state.trashSettings = nil
            case .versions: state.versionedFiles = nil
            }
            return .none

        case .offlineDownloadButtonTapped:
            state.offlineSelection = OfflineSelectionFeature.State(serverURL: state.serverURL)
            return .none

        case let .offlineSelection(.presented(.delegate(.confirmed(items)))):
            state.offlineSelection = nil
            return .send(.delegate(.startOfflineDownload(items)))

        case .offlineSelection(.presented(.delegate(.cancelled))):
            state.offlineSelection = nil
            return .none

        case .offlineSelection:
            return .none

        case .offlineManageButtonTapped:
            state.offlineManage = OfflineManageFeature.State()
            return .none

        case .offlineManage(.presented(.delegate(.changed))):
            return .send(.refreshOfflineSize)

        case .offlineManage:
            return .none

        case .cancelOfflineDownloadTapped:
            return .send(.delegate(.cancelOfflineDownload))

        case .resyncOfflineTapped:
            return .send(.delegate(.resyncOffline))

        case .removeOfflineTapped:
            state.removeOfflineConfirmationIsPresented = true
            return .none

        case .removeOfflineCancelled:
            state.removeOfflineConfirmationIsPresented = false
            return .none

        case .removeOfflineConfirmed:
            state.removeOfflineConfirmationIsPresented = false
            state.offlineSize = 0
            return .send(.delegate(.removeOfflineFiles))

        case .refreshOfflineSize:
            let offlineFileStore = offlineFileStore
            return .run { send in
                await send(.offlineSizeResponse(offlineFileStore.totalSizeBytes()))
            }
            .cancellable(id: CancelID.offlineSize, cancelInFlight: true)

        case let .offlineSizeResponse(size):
            state.offlineSize = size
            return .none

        case .tipJarButtonTapped:
            state.tipJar = TipJarFeature.State()
            return .none

        case .tipJar(.presented(.delegate(.tipped))):
            state.tipJar = nil
            state.tipToast = L10n.TipJar.toastThanks
            return .none

        case .tipJar:
            return .none

        case .clientCertificateButtonTapped:
            guard let origin = ClientCertificateOrigin(url: state.serverURL) else { return .none }
            state.clientCertificate = ClientCertificateFeature.State(origin: origin, status: state.clientCertificateStatus)
            return .none

        case let .clientCertificateStatusLoaded(summary):
            state.clientCertificateStatus = summary.map(ClientCertificateFeature.Status.installed) ?? .empty
            return .none

        case let .clientCertificate(.presented(.delegate(.installed(summary)))):
            state.clientCertificateStatus = .installed(summary)
            return .none

        case .clientCertificate(.presented(.delegate(.removed))):
            state.clientCertificateStatus = .empty
            return .none

        case .clientCertificate, .uploadDefaults:
            return .none

        case .tipToastShown:
            state.tipToast = nil
            return .none

        case let .brandingResponse(.success(branding)):
            state.$branding.withLock { $0 = branding }
            return .none

        case .brandingResponse(.failure):
            return .none

        case let .serverFeaturesResponse(features):
            state.isVolumeUsageEnabled = features.isVolumeUsageEnabled
            guard features.isVolumeUsageEnabled else { return .none }
            let serverURL = state.serverURL
            let filesClient = filesClient
            return .run { send in
                guard let volumes = try? await filesClient.volumes(serverURL) else { return }
                await send(.volumesResponse(volumes))
            }
            .cancellable(id: CancelID.serverUsage, cancelInFlight: true)

        case let .volumesResponse(volumes):
            state.serverUsage = IdentifiedArray(
                volumes.map { VolumeUsage(volume: $0, usage: nil) },
                id: \.id, uniquingIDsWith: { first, _ in first }
            )
            let serverURL = state.serverURL
            let filesClient = filesClient
            return .merge(volumes.map { volume in
                .run { send in
                    try await send(.serverUsageResponse(
                        path: volume.path,
                        apiResult { try await filesClient.fetchUsage(serverURL, volume.path) }
                    ))
                }
            })
            .cancellable(id: CancelID.volumeUsage, cancelInFlight: false)

        case let .serverUsageResponse(path, .success(usage)):
            state.serverUsage[id: path]?.usage = usage
            return .none

        case .serverUsageResponse(_, .failure):
            return .none

        case .onAppear:
            let localDownloadStore = localDownloadStore
            let previewCacheStore = previewCacheStore
            let downloadScope = state.downloadScope
            let checkDownloads = Effect<Action>.run { send in
                let downloads = (try? localDownloadStore.list(downloadScope)) ?? []
                await send(.hasDownloadsResponse(!downloads.isEmpty))
                await send(.downloadsSizeResponse(downloads.reduce(0) { $0 + $1.size }))
            }
            let directoryCacheStore = directoryCacheStore
            let jsonCacheStore = jsonCacheStore
            let checkCacheSize = Effect<Action>.run { send in
                let size = (try? previewCacheStore.size()) ?? 0
                await send(.cacheSizeResponse(size + directoryCacheStore.totalSizeBytes() + jsonCacheStore.totalSizeBytes()))
            }
            let offlineFileStore = offlineFileStore
            let checkOfflineSize = Effect<Action>.run { send in
                await send(.offlineSizeResponse(offlineFileStore.totalSizeBytes()))
            }
            let clientCertificateClient = clientCertificateClient
            let certificateOrigin = ClientCertificateOrigin(url: state.serverURL)
            let checkClientCertificate = Effect<Action>.run { send in
                guard let certificateOrigin else { return }
                await send(.clientCertificateStatusLoaded(clientCertificateClient.summary(certificateOrigin)))
            }
            let loadUploadDefaults = Effect<Action>.send(.uploadDefaults(.onAppear))
            guard !state.isLoadingPreferences else {
                return .merge(checkDownloads, checkCacheSize, checkOfflineSize, checkClientCertificate, loadUploadDefaults)
            }
            state.isLoadingPreferences = true
            let serverURL = state.serverURL
            let filesClient = filesClient
            let loadAuthMethods = Effect<Action>.run { send in
                try await send(.authMethodsResponse(apiResult { try await filesClient.fetchAuthMethods(serverURL) }))
            }
            .cancellable(id: CancelID.authMethods, cancelInFlight: true)
            let loadAuthStatus = Effect<Action>.run { send in
                try await send(.authStatusResponse(apiResult { try await filesClient.fetchAuthStatus(serverURL) }))
            }
            .cancellable(id: CancelID.authStatus, cancelInFlight: true)
            return .merge(
                loadAuthMethods,
                loadAuthStatus,
                checkDownloads,
                checkCacheSize,
                checkOfflineSize,
                checkClientCertificate,
                loadUploadDefaults,
                .run { send in
                    try await send(.brandingResponse(apiResult { try await filesClient.fetchBranding(serverURL) }))
                },
                .run { send in
                    guard let features = try? await filesClient.serverFeatures(serverURL) else { return }
                    await send(.serverFeaturesResponse(features))
                },
                .run { send in
                    try await send(.preferencesResponse(apiResult {
                        try await filesClient.fetchPreferences(serverURL)
                    }))
                }
            )

        case let .preferencesResponse(.success(preferences)):
            state.isLoadingPreferences = false
            state.$preferences.withLock { $0 = preferences }
            return .none

        case .preferencesResponse(.failure):
            state.isLoadingPreferences = false
            return .none

        case let .setShowHiddenFiles(value):
            state.$preferences.withLock { $0.showHiddenFiles = value }
            return updatePreference(.showHiddenFiles, value, state: &state)

        case let .setShowThumbnails(value):
            state.$preferences.withLock { $0.showThumbnails = value }
            return updatePreference(.showThumbnails, value, state: &state)

        case .updatePreferenceResponse:
            return .none

        case .signOutButtonTapped:
            state.isConfirmingSignOut = true
            return .none

        case .cancelSignOutTapped:
            state.isConfirmingSignOut = false
            return .none

        case .confirmSignOutTapped:
            // Keep the confirmation sheet up: the parent flips `isSigningOut`, which drives
            // the sheet's confirm spinner, and the whole authenticated scope (this sheet
            // with it) is torn down once sign out finishes.
            return .send(.delegate(.signOutButtonTapped))

        case let .switchAccountTapped(id):
            // Tapping the already-active account is a no-op.
            guard state.accounts.first(where: { $0.id == id })?.isActive != true else { return .none }
            return .send(.delegate(.switchAccount(id)))

        case .addAccountTapped:
            return .send(.delegate(.addAccountRequested))

        case let .removeAccountTapped(account):
            state.accountPendingRemoval = account
            return .none

        case .removeAccountCancelled:
            state.accountPendingRemoval = nil
            return .none

        case .removeAccountConfirmed:
            guard let id = state.accountPendingRemoval?.id else { return .none }
            state.accountPendingRemoval = nil
            return .send(.delegate(.removeAccount(id)))

        case .removeAllDownloadsTapped:
            state.removeAllDownloadsConfirmationIsPresented = true
            return .none

        case .removeAllDownloadsCancelled:
            state.removeAllDownloadsConfirmationIsPresented = false
            return .none

        case .removeAllDownloadsConfirmed:
            state.removeAllDownloadsConfirmationIsPresented = false
            state.isRemovingAllDownloads = true
            let localDownloadStore = localDownloadStore
            let downloadScope = state.downloadScope
            return .run { send in
                // Best-effort, matching the sign-out flow's philosophy: one file
                // refusing to delete shouldn't block clearing the rest.
                let downloads = (try? localDownloadStore.list(downloadScope)) ?? []
                for download in downloads {
                    try? localDownloadStore.delete(download.url)
                }
                await send(.removeAllDownloadsResponse)
            }

        case .removeAllDownloadsResponse:
            state.isRemovingAllDownloads = false
            state.hasDownloads = false
            state.downloadsSize = 0
            return .send(.delegate(.allDownloadsRemoved))

        case let .hasDownloadsResponse(hasDownloads):
            state.hasDownloads = hasDownloads
            return .none

        case let .downloadsSizeResponse(size):
            state.downloadsSize = size
            return .none

        case let .cacheSizeResponse(size):
            state.cacheSize = size
            return .none

        case .clearCacheTapped:
            state.clearCacheConfirmationIsPresented = true
            return .none

        case .clearCacheCancelled:
            state.clearCacheConfirmationIsPresented = false
            return .none

        case .clearCacheConfirmed:
            state.clearCacheConfirmationIsPresented = false
            state.isClearingCache = true
            let previewCacheStore = previewCacheStore
            let directoryCacheStore = directoryCacheStore
            let jsonCacheStore = jsonCacheStore
            let thumbnailCache = thumbnailCache
            return .run { send in
                try? previewCacheStore.clear()
                directoryCacheStore.clearAll()
                jsonCacheStore.clearAll()
                thumbnailCache.clearMemory()
                await send(.clearCacheResponse)
            }

        case .clearCacheResponse:
            state.isClearingCache = false
            state.cacheSize = 0
            return .none

        case .delegate:
            return .none
        }
    }

    public var body: some ReducerOf<Self> {
        Scope(state: \.uploadDefaults, action: \.uploadDefaults) {
            UploadDefaultsFeature()
        }
        Reduce(core(into:action:))
            .ifLet(\.$userManagement, action: \.userManagement) {
                UserManagementFeature()
            }
            .ifLet(\.$changePassword, action: \.changePassword) {
                ChangePasswordFeature()
            }
            .ifLet(\.$twoFactor, action: \.twoFactor) {
                TwoFactorFeature()
            }
            .ifLet(\.$apiTokens, action: \.apiTokens) {
                APITokensFeature()
            }
            .ifLet(\.$serverDetails, action: \.serverDetails) {
                ServerDetailsFeature()
            }
            .ifLet(\.$thumbnailSettings, action: \.thumbnailSettings) {
                ThumbnailSettingsFeature()
            }
            .ifLet(\.$accessRules, action: \.accessRules) {
                AccessRulesFeature()
            }
            .ifLet(\.$offlineSelection, action: \.offlineSelection) {
                OfflineSelectionFeature()
            }
            .ifLet(\.$offlineManage, action: \.offlineManage) {
                OfflineManageFeature()
            }
            .ifLet(\.$clientCertificate, action: \.clientCertificate) {
                ClientCertificateFeature()
            }
            .ifLet(\.$tipJar, action: \.tipJar) {
                TipJarFeature()
            }
        // Its own chain: one more `ifLet` on the one above is too much for the type checker.
        EmptyReducer()
            .ifLet(\.$uploadSettings, action: \.uploadSettings) {
                UploadSettingsFeature()
            }
            .ifLet(\.$ffmpegSettings, action: \.ffmpegSettings) {
                FFmpegSettingsFeature()
            }
            .ifLet(\.$searchIndexSettings, action: \.searchIndexSettings) {
                SearchIndexSettingsFeature()
            }
            .ifLet(\.$folderSizeSettings, action: \.folderSizeSettings) {
                FolderSizeSettingsFeature()
            }
        EmptyReducer()
            .ifLet(\.$activityLog, action: \.activityLog) {
                ActivityLogFeature()
            }
            .ifLet(\.$trashSettings, action: \.trashSettings) {
                TrashSettingsFeature()
            }
            .ifLet(\.$versionedFiles, action: \.versionedFiles) {
                VersionedFilesFeature()
            }
    }

    /// Fire-and-forget: the toggle already updated optimistically, so a failed PATCH just
    /// means the server falls out of sync with the switch until the next successful one.
    private func updatePreference(_ key: UserPreferenceKey, _ value: Bool, state: inout State) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.updatePreferenceResponse(apiResult {
                try await filesClient.updatePreference(serverURL, key, value)
            }))
        }
        // Per key, so hammering one toggle converges the server on the latest value instead of
        // letting an earlier PATCH land last and leave the server out of sync with the switch.
        .cancellable(id: CancelID.preference(key), cancelInFlight: true)
    }
}
