import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation

@Reducer
public struct LockFeature {
    @ObservableState
    public struct State: Equatable {
        public var account: AccountSummary
        public var ssoPhase: SSOPhase = .idle
        public var problem: Problem?
        public var signOut: ConfirmPhase = .idle
        @Presents public var signIn: LoginFormFeature.State?
        @SharedReader(.inMemory(AccountSummary.sharedKey)) public var accounts: [AccountSummary] = []
        var pendingSignIn: SignedIn?

        public init(account: AccountSummary) {
            self.account = account
        }

        public var shouldUnlockWithSSO: Bool {
            account.authMode == .oidc
        }

        public var switchableAccounts: [AccountSummary] {
            accounts.count > 1 ? accounts : []
        }

        public var isBusy: Bool {
            ssoPhase == .signingIn || signOut.isRunning
        }
    }

    public enum SSOPhase: Equatable, Sendable {
        case idle
        case signingIn
    }

    public enum Problem: Equatable, Sendable {
        case signInFailed(AuthClientError)
        case otherAccount
        case signOutFailed
    }

    public struct SignedIn: Equatable, Sendable {
        public let user: User
        public let serverURL: URL
    }

    public enum Action {
        case ssoButtonTapped
        case ssoResponse(Result<User, AuthClientError>)
        case signInButtonTapped
        case signIn(PresentationAction<LoginFormFeature.Action>)
        case signInSheetDismissed
        case signOutButtonTapped
        case signOutCancelled
        case signOutConfirmed
        case otherAccountRefused
        case signOutFailed
        case accountTapped(String)
        case delegate(Delegate)
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
        case signedIn(User, URL)
        case signOutRequested
        case switchAccount(String)
    }

    private enum CancelID {
        case sso
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .ssoButtonTapped:
                guard !state.isBusy else { return .none }
                state.ssoPhase = .signingIn
                state.problem = nil
                let authClient = authClient
                let serverURL = state.account.serverURL
                return .run { send in
                    let result = await LoginFormFeature.loginOIDCResult(
                        authClient,
                        serverURL,
                        browserSession: .ephemeral
                    )
                    await send(.ssoResponse(result))
                }
                .cancellable(id: CancelID.sso, cancelInFlight: true)

            case let .ssoResponse(.success(user)):
                state.ssoPhase = .idle
                return .send(.delegate(.signedIn(user, state.account.serverURL)))

            case let .ssoResponse(.failure(error)):
                state.ssoPhase = .idle
                if error != .oidcCancelled {
                    state.problem = .signInFailed(error)
                }
                return .none

            case .signInButtonTapped:
                guard !state.isBusy else { return .none }
                state.problem = nil
                var login = LoginFormFeature.State(
                    scheme: state.account.serverURL.scheme == LoginFormFeature.URLScheme.http.rawValue ? .http : .https,
                    host: state.account.serverHost,
                    identifier: [state.account.email, state.account.username]
                        .compactMap(\.self)
                        .first { !$0.isEmpty } ?? ""
                )
                login.browserSession = .ephemeral
                state.signIn = login
                return .send(.signIn(.presented(.testConnectionButtonTapped)))

            case let .signIn(.presented(.delegate(.authenticated(user, serverURL)))):
                state.pendingSignIn = SignedIn(user: user, serverURL: serverURL)
                state.signIn = nil
                return .none

            case .signInSheetDismissed:
                guard let signedIn = state.pendingSignIn else { return .none }
                state.pendingSignIn = nil
                return .send(.delegate(.signedIn(signedIn.user, signedIn.serverURL)))

            case .signOutButtonTapped:
                guard !state.isBusy else { return .none }
                state.signOut.ask()
                return .none

            case .signOutCancelled:
                state.signOut.cancel()
                return .none

            case .signOutConfirmed:
                guard state.signOut.isConfirming else { return .none }
                state.signOut = .running
                state.problem = nil
                return .send(.delegate(.signOutRequested))

            case .otherAccountRefused:
                state.ssoPhase = .idle
                state.problem = .otherAccount
                return .none

            case .signOutFailed:
                state.signOut = .idle
                state.problem = .signOutFailed
                return .none

            case let .accountTapped(accountID):
                guard accountID != state.account.id, !state.isBusy else { return .none }
                return .send(.delegate(.switchAccount(accountID)))

            case .signIn, .delegate:
                return .none
            }
        }
        .ifLet(\.$signIn, action: \.signIn) {
            LoginFormFeature()
        }
    }
}

public extension LockFeature.State {
    static func preview(authMode: AuthMode) -> Self {
        let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
        return Self(
            account: AccountSummary(
                id: SessionCredentials.accountID(serverURL: serverURL, username: "alex"),
                username: "alex",
                serverURL: serverURL,
                isActive: true,
                authMode: authMode,
                requireSignIn: RequireSignIn(),
                isLocked: true
            )
        )
    }
}
