import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// The signed in account's API tokens, mirroring the web client: a list, a form to make one, the
/// secret shown once, a rename and a revoke. Every route is reached with a session, never with a
/// token, and an installation without accounts answers 403 with a message.
@Reducer
public struct APITokensFeature {
    public enum Phase: Equatable, Sendable {
        case loading
        case failed(String)
        case loaded
    }

    /// How long a new token lasts. The server takes a number of days or none.
    public enum Expiry: CaseIterable, Equatable, Sendable {
        case days30
        case days90
        case year
        case never

        public var days: Int? {
            switch self {
            case .days30: 30
            case .days90: 90
            case .year: 365
            case .never: nil
            }
        }
    }

    public struct CreateForm: Equatable, Sendable {
        public var name = ""
        public var scope: APIToken.Scope = .read
        public var expiry: Expiry = .days90
        public var password = ""

        public init(name: String = "", scope: APIToken.Scope = .read, expiry: Expiry = .days90, password: String = "") {
            self.name = name
            self.scope = scope
            self.expiry = expiry
            self.password = password
        }
    }

    public struct Rename: Equatable, Sendable {
        public let id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        /// Whether the account has a password to ask for. The server only checks one when it does.
        public let requiresPassword: Bool
        public var phase: Phase = .loading
        public var tokens: [APIToken] = []
        /// One request in flight at a time: the screen has a single action under way.
        public var isWorking = false
        public var errorMessage: String?
        public var createForm: CreateForm?
        public var issued: IssuedAPIToken?
        public var rename: Rename?
        public var tokenPendingRevoke: APIToken?

        public init(serverURL: URL, requiresPassword: Bool = true, phase: Phase = .loading, tokens: [APIToken] = []) {
            self.serverURL = serverURL
            self.requiresPassword = requiresPassword
            self.phase = phase
            self.tokens = tokens
        }

        public var hasReachedLimit: Bool {
            tokens.count >= APITokenLimits.maxTokensPerAccount
        }

        public var isCreateEnabled: Bool {
            guard let form = createForm, !isWorking else { return false }
            return APITokensFeature.isValid(name: form.name) && (!requiresPassword || !form.password.isEmpty)
        }

        public var isRenameEnabled: Bool {
            guard let rename, !isWorking else { return false }
            return APITokensFeature.isValid(name: rename.name)
        }
    }

    public enum Action: Equatable, Sendable {
        case task
        case retryTapped
        case listResponse(Result<[APIToken], FilesClientError>)
        case newTokenTapped
        case nameChanged(String)
        case scopeChanged(APIToken.Scope)
        case expiryChanged(Expiry)
        case passwordChanged(String)
        case createCancelled
        case createSubmitted
        case createResponse(Result<IssuedAPIToken, FilesClientError>)
        case issuedDismissed
        case renameTapped(APIToken)
        case renameNameChanged(String)
        case renameCancelled
        case renameSubmitted
        case renameResponse(Result<APIToken, FilesClientError>)
        case revokeTapped(APIToken)
        case revokeCancelled
        case revokeConfirmed
        case revokeResponse(Result<String, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID {
        case load
        case action
    }

    public init() {}

    /// The server trims a name and cuts it at the limit, and refuses an empty one.
    static func isValid(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= APITokenLimits.maxNameLength
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .retryTapped:
                state.phase = .loading
                state.errorMessage = nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    try await send(.listResponse(apiResult { try await filesClient.fetchAPITokens(serverURL) }))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .listResponse(.success(tokens)):
                state.tokens = tokens
                state.phase = .loaded
                return .none

            case let .listResponse(.failure(error)):
                state.phase = .failed(error.userMessage)
                return .none

            case .newTokenTapped:
                guard state.phase == .loaded, !state.hasReachedLimit, !state.isWorking else { return .none }
                state.errorMessage = nil
                state.createForm = CreateForm()
                return .none

            case let .nameChanged(name):
                state.createForm?.name = name
                return .none

            case let .scopeChanged(scope):
                state.createForm?.scope = scope
                return .none

            case let .expiryChanged(expiry):
                state.createForm?.expiry = expiry
                return .none

            case let .passwordChanged(password):
                state.createForm?.password = password
                return .none

            case .createCancelled:
                state.createForm = nil
                state.errorMessage = nil
                state.isWorking = false
                return .cancel(id: CancelID.action)

            case .createSubmitted:
                guard let form = state.createForm, state.isCreateEnabled else { return .none }
                state.isWorking = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let password = state.requiresPassword ? form.password : nil
                let filesClient = filesClient
                return .run { send in
                    try await send(.createResponse(apiResult {
                        try await filesClient.createAPIToken(serverURL, name, form.scope, form.expiry.days, password)
                    }))
                }
                .cancellable(id: CancelID.action, cancelInFlight: true)

            case let .createResponse(.success(issued)):
                state.isWorking = false
                state.createForm = nil
                state.tokens.append(issued.token)
                state.issued = issued
                return .none

            case let .createResponse(.failure(error)):
                state.isWorking = false
                state.errorMessage = error.userMessage
                // A wrong password is typed again, so the field does not keep it.
                if case .serverMessage(401, _) = error {
                    state.createForm?.password = ""
                }
                return .none

            case .issuedDismissed:
                state.issued = nil
                return .none

            case let .renameTapped(token):
                guard !state.isWorking else { return .none }
                state.errorMessage = nil
                state.rename = Rename(id: token.id, name: token.name)
                return .none

            case let .renameNameChanged(name):
                state.rename?.name = name
                return .none

            case .renameCancelled:
                state.rename = nil
                state.errorMessage = nil
                return .none

            case .renameSubmitted:
                guard let rename = state.rename, state.isRenameEnabled else { return .none }
                state.isWorking = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let name = rename.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let filesClient = filesClient
                return .run { send in
                    try await send(.renameResponse(apiResult { try await filesClient.renameAPIToken(serverURL, rename.id, name) }))
                }
                .cancellable(id: CancelID.action, cancelInFlight: true)

            case let .renameResponse(.success(token)):
                state.isWorking = false
                state.rename = nil
                if let index = state.tokens.firstIndex(where: { $0.id == token.id }) {
                    state.tokens[index] = token
                }
                return .none

            case let .renameResponse(.failure(error)):
                state.isWorking = false
                state.rename = nil
                state.errorMessage = error.userMessage
                return .none

            case let .revokeTapped(token):
                guard !state.isWorking else { return .none }
                state.errorMessage = nil
                state.tokenPendingRevoke = token
                return .none

            case .revokeCancelled:
                state.tokenPendingRevoke = nil
                return .none

            case .revokeConfirmed:
                guard let token = state.tokenPendingRevoke, !state.isWorking else { return .none }
                state.tokenPendingRevoke = nil
                state.isWorking = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    try await send(.revokeResponse(apiResult {
                        try await filesClient.revokeAPIToken(serverURL, token.id)
                        return token.id
                    }))
                }
                .cancellable(id: CancelID.action, cancelInFlight: true)

            case let .revokeResponse(.success(id)):
                state.isWorking = false
                state.tokens.removeAll { $0.id == id }
                return .none

            case let .revokeResponse(.failure(error)):
                state.isWorking = false
                state.errorMessage = error.userMessage
                return .none
            }
        }
    }
}
