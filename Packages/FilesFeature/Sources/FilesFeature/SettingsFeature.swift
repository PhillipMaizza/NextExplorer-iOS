import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// Account info, the two `user_settings` preferences that affect anything this app has
/// built (`showHiddenFiles`, `showThumbnails`, see `UserPreferences`), and sign out.
/// The sign-out network call itself is owned by the parent (`AuthenticatedFeature`,
/// which already holds `authClient`); this only surfaces the confirmed tap and
/// displays whatever `isSigningOut` the parent drives back down.
@Reducer
public struct SettingsFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var user: User
        public var isSigningOut = false
        public var isConfirmingSignOut = false
        /// Shared with `BrowseFeature` under the same in-memory key, so toggling
        /// "Show Hidden Files" here is reflected immediately in an already-open folder.
        @Shared(.inMemory("userPreferences")) public var preferences = UserPreferences()
        public var isLoadingPreferences = false
        public var removeAllDownloadsConfirmationIsPresented = false
        public var isRemovingAllDownloads = false
        /// Checked independently of the Downloads tab's own state (which may never have
        /// loaded, if the user hasn't visited that tab this session) — this is what actually
        /// disables "Remove All Downloads" until there's proof there's nothing to remove.
        public var hasDownloads = true
        public var downloadsSize: Int64 = 0
        public var cacheSize: Int64 = 0
        public var isClearingCache = false
        public var clearCacheConfirmationIsPresented = false

        public var displayName: String { user.displayName ?? user.username }

        public init(serverURL: URL, user: User) {
            self.serverURL = serverURL
            self.user = user
        }
    }

    public enum Action: Sendable {
        case onAppear
        case preferencesResponse(Result<UserPreferences, FilesClientError>)
        case setShowHiddenFiles(Bool)
        case setShowThumbnails(Bool)
        case updatePreferenceResponse(Result<Void, FilesClientError>)
        case signOutButtonTapped
        case cancelSignOutTapped
        case confirmSignOutTapped
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
            /// Every local download was just deleted — `MainTabFeature` clears the
            /// Downloads tab's list without waiting for it to re-scan the (now empty) disk.
            case allDownloadsRemoved
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.localDownloadStore) var localDownloadStore
    @Dependency(\.previewCacheStore) var previewCacheStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let localDownloadStore = self.localDownloadStore
                let previewCacheStore = self.previewCacheStore
                let checkDownloads = Effect<Action>.run { send in
                    let downloads = (try? localDownloadStore.list()) ?? []
                    await send(.hasDownloadsResponse(!downloads.isEmpty))
                    await send(.downloadsSizeResponse(downloads.reduce(0) { $0 + $1.size }))
                }
                let checkCacheSize = Effect<Action>.run { send in
                    let size = (try? previewCacheStore.size()) ?? 0
                    await send(.cacheSizeResponse(size))
                }
                guard !state.isLoadingPreferences else { return .merge(checkDownloads, checkCacheSize) }
                state.isLoadingPreferences = true
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .merge(
                    checkDownloads,
                    checkCacheSize,
                    .run { send in
                        do {
                            let preferences = try await filesClient.fetchPreferences(serverURL)
                            await send(.preferencesResponse(.success(preferences)))
                        } catch {
                            await send(.preferencesResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
                        }
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
                state.isConfirmingSignOut = false
                return .send(.delegate(.signOutButtonTapped))

            case .removeAllDownloadsTapped:
                state.removeAllDownloadsConfirmationIsPresented = true
                return .none

            case .removeAllDownloadsCancelled:
                state.removeAllDownloadsConfirmationIsPresented = false
                return .none

            case .removeAllDownloadsConfirmed:
                state.removeAllDownloadsConfirmationIsPresented = false
                state.isRemovingAllDownloads = true
                let localDownloadStore = self.localDownloadStore
                return .run { send in
                    // Best-effort, matching the sign-out flow's philosophy: one file
                    // refusing to delete shouldn't block clearing the rest.
                    let downloads = (try? localDownloadStore.list()) ?? []
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
                let previewCacheStore = self.previewCacheStore
                return .run { send in
                    try? previewCacheStore.clear()
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
    }

    /// Fire-and-forget: the toggle already updated optimistically, so a failed PATCH just
    /// means the server falls out of sync with the switch until the next successful one.
    private func updatePreference(_ key: UserPreferenceKey, _ value: Bool, state: inout State) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            do {
                try await filesClient.updatePreference(serverURL, key, value)
                await send(.updatePreferenceResponse(.success(())))
            } catch {
                await send(.updatePreferenceResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }
}
