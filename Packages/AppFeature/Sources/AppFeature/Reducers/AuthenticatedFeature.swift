import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation

@Reducer
public struct AuthenticatedFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var user: User
        public var mainTab: MainTabFeature.State

        public init(serverURL: URL, user: User) {
            self.serverURL = serverURL
            self.user = user
            mainTab = MainTabFeature.State(serverURL: serverURL, user: user)
        }

        /// This account's stable identity, matching `SessionCredentials.accountID`.
        var accountID: String {
            Self.accountID(serverURL: serverURL, username: user.username)
        }

        static func accountID(serverURL: URL, username: String) -> String {
            [serverURL.absoluteString, username].joined(separator: Constants.accountIDSeparator)
        }
    }

    public enum Action: Sendable {
        case mainTab(MainTabFeature.Action)
        /// The active account changed as a result of a switch / sign out / removal performed here;
        /// carries the account now active (`nil` when none remain).
        case accountChangeResolved(SessionCredentials?)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// The active account changed (or, with `nil`, the last account was signed out).
            /// `AppFeature` remounts the authenticated UI or drops to login.
            case activeAccountChanged(SessionCredentials?)
            /// The user asked to add another server; `AppFeature` presents the login sheet.
            case addAccountRequested
        }
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock

    private var accountCacheWipe: AccountCacheWipe {
        .fromDependencies
    }

    private enum Constants {
        static let accountIDSeparator = "|"
        /// How long the sign out confirmation takes to slide away, so the login screen is not
        /// revealed underneath it.
        static let promptDismissDuration: Duration = .seconds(0.4)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.mainTab, action: \.mainTab) {
            MainTabFeature()
        }
        Reduce { state, action in
            switch action {
            case .mainTab(.delegate(.signOutButtonTapped)):
                // The top "Sign Out" signs the ACTIVE account out and hands off to the next
                // remaining account, if any. This account's cached data is removed here; the full
                // teardown (every store, preferences) is done by `AppFeature` once the delegate
                // below reports no account is left.
                state.mainTab.settings.isSigningOut = true
                let accountID = state.accountID
                let authClient = authClient
                let accountCacheWipe = accountCacheWipe
                return .run { send in
                    accountCacheWipe.markPending(accountID)
                    let next = await authClient.removeAccount(accountID)
                    accountCacheWipe.wipe(accountID)
                    await send(.accountChangeResolved(next))
                }

            case let .mainTab(.delegate(.switchAccount(accountID))):
                let authClient = authClient
                return .run { send in
                    let switched = await authClient.switchAccount(accountID)
                    await send(.accountChangeResolved(switched))
                }

            case let .mainTab(.delegate(.removeAccount(accountID))):
                let authClient = authClient
                let accountCacheWipe = accountCacheWipe
                return .run { send in
                    accountCacheWipe.markPending(accountID)
                    let next = await authClient.removeAccount(accountID)
                    accountCacheWipe.wipe(accountID)
                    await send(.accountChangeResolved(next))
                }

            case .mainTab(.delegate(.addAccountRequested)):
                return .send(.delegate(.addAccountRequested))

            case let .accountChangeResolved(credentials):
                guard credentials == nil else {
                    state.mainTab.settings.isSigningOut = false
                    return .send(.delegate(.activeAccountChanged(credentials)))
                }
                // The last account is gone and `AppFeature` is about to swap in the login screen.
                // Close the confirmation first and let it finish sliding away: swapping at once
                // leaves it hanging over the login screen until UIKit gets round to dismissing it.
                state.mainTab.settings.isConfirmingSignOut = false
                state.mainTab.settings.accountPendingRemoval = nil
                let clock = clock
                return .run { send in
                    try await clock.sleep(for: Constants.promptDismissDuration)
                    await send(.delegate(.activeAccountChanged(nil)))
                }

            case .mainTab, .delegate:
                return .none
            }
        }
    }
}
