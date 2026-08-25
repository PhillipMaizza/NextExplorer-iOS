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
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case signOutButtonTapped
        }
    }

    @Dependency(\.filesClient) var filesClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.isLoadingPreferences else { return .none }
                state.isLoadingPreferences = true
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    do {
                        let preferences = try await filesClient.fetchPreferences(serverURL)
                        await send(.preferencesResponse(.success(preferences)))
                    } catch {
                        await send(.preferencesResponse(.failure((error as? FilesClientError) ?? .network(String(describing: error)))))
                    }
                }

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
