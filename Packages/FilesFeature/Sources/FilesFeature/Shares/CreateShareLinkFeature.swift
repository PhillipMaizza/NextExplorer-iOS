import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

/// Drives the "Create Share Link" sheet (`CreateShareLinkSheet`) — mirrors the web client's
/// `ShareDialog.vue`. Two phases in one state: the form, then the created-link confirmation
/// (`createdShare != nil`). Verified request/response shapes: [[share-link-api]].
@Reducer
public struct CreateShareLinkFeature {
    /// Days ahead the expiration date defaults to when the user first enables it.
    static let defaultExpiryDays: Double = 7

    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var itemName: String
        public var itemPath: String
        public var isDirectory: Bool

        public var label: String
        public var accessMode: ShareAccessMode = .readonly
        public var target: ShareTarget = .anyone
        public var isPasswordEnabled = false
        public var password = ""
        public var isExpiryEnabled = false
        public var expiresAt: Date
        /// Set once the user changes the expiry toggle or date, so a late-arriving
        /// preferences fetch doesn't stomp on their choice.
        var hasTouchedExpiry = false

        public var isCreating = false
        public var errorMessage: String?
        public var createdShare: CreatedShare?
        public var directLinkMode: DirectLinkMode = .auto

        /// Shareable-users list, loaded the first time "Specific users" is chosen.
        public var shareableUsers: IdentifiedArrayOf<User> = []
        public var selectedUserIDs: Set<User.ID> = []
        public var usersPhase: DataPhase = .idle
        /// Shared with `SharedFeature` — bumping it makes the Shared tab reload.
        @Shared(.inMemory(SharedFeature.revisionKey)) var shareLinksRevision = 0

        public init(serverURL: URL, itemName: String, itemPath: String, isDirectory: Bool, now: Date = Date()) {
            self.serverURL = serverURL
            self.itemName = itemName
            self.itemPath = itemPath
            self.isDirectory = isDirectory
            self.label = itemName
            self.expiresAt = now.addingTimeInterval(defaultExpiryDays * 24 * 60 * 60)
        }

        /// Full logical path of the shared item — parent path plus name, matching the
        /// server's `sourcePath` expectation.
        public var sourcePath: String {
            itemPath.isEmpty ? itemName : "\(itemPath)/\(itemName)"
        }

        public var isCreateEnabled: Bool {
            guard !isCreating else { return false }
            if target == .users {
                return !selectedUserIDs.isEmpty
            }
            return true
        }

        public var directLink: URL? {
            createdShare?.directLink(mode: directLinkMode)
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case preferencesResponse(UserPreferences)
        case labelChanged(String)
        case accessModeChanged(ShareAccessMode)
        case targetChanged(ShareTarget)
        case passwordEnabledChanged(Bool)
        case passwordChanged(String)
        case expiryEnabledChanged(Bool)
        case expiresAtChanged(Date)
        case directLinkModeChanged(DirectLinkMode)
        case userToggled(User.ID)
        case shareableUsersResponse(Result<[User], FilesClientError>)
        case createTapped
        case createResponse(Result<CreatedShare, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.date) var date
    @Dependency(\.calendar) var calendar

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    guard let preferences = try? await filesClient.fetchPreferences(serverURL) else { return }
                    await send(.preferencesResponse(preferences))
                }

            case let .preferencesResponse(preferences):
                // Match the web client: a user with a default expiration set gets expiry
                // switched on and pre dated when the sheet opens. Skipped once the user has
                // already touched the expiry controls.
                guard !state.hasTouchedExpiry,
                      let expiration = preferences.defaultShareExpiration,
                      let expiresAt = expiration.expirationDate(from: date.now, calendar: calendar)
                else { return .none }
                state.isExpiryEnabled = true
                state.expiresAt = expiresAt
                return .none

            case let .labelChanged(label):
                state.label = label
                return .none

            case let .accessModeChanged(mode):
                state.accessMode = mode
                state.errorMessage = nil
                return .none

            case let .targetChanged(target):
                state.target = target
                state.errorMessage = nil
                guard target == .users, state.usersPhase.shouldLoadOnAppear else { return .none }
                state.usersPhase = .loading
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.shareableUsersResponse(try await apiResult {
                        try await filesClient.shareableUsers(serverURL)
                    }))
                }

            case let .shareableUsersResponse(.success(users)):
                state.usersPhase = .loaded
                state.shareableUsers = IdentifiedArray(users, id: \.id, uniquingIDsWith: { first, _ in first })
                return .none

            case let .shareableUsersResponse(.failure(error)):
                state.usersPhase = .failed(error.userMessage)
                state.errorMessage = error.userMessage
                return .none

            case let .userToggled(id):
                if state.selectedUserIDs.contains(id) {
                    state.selectedUserIDs.remove(id)
                } else {
                    state.selectedUserIDs.insert(id)
                }
                return .none

            case let .passwordEnabledChanged(isEnabled):
                state.isPasswordEnabled = isEnabled
                return .none

            case let .passwordChanged(password):
                state.password = password
                return .none

            case let .expiryEnabledChanged(isEnabled):
                state.isExpiryEnabled = isEnabled
                state.hasTouchedExpiry = true
                return .none

            case let .expiresAtChanged(date):
                state.expiresAt = date
                state.hasTouchedExpiry = true
                return .none

            case let .directLinkModeChanged(mode):
                state.directLinkMode = mode
                return .none

            case .createTapped:
                guard state.isCreateEnabled else { return .none }
                if state.isExpiryEnabled, state.expiresAt <= date.now {
                    state.errorMessage = L10n.CreateShare.errorPastExpiration
                    return .none
                }
                state.isCreating = true
                state.errorMessage = nil
                let request = CreateShareLinkRequest(
                    sourcePath: state.sourcePath,
                    label: state.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : state.label.trimmingCharacters(in: .whitespacesAndNewlines),
                    accessMode: state.accessMode,
                    target: state.target,
                    password: state.isPasswordEnabled && !state.password.isEmpty ? state.password : nil,
                    userIds: state.target == .users ? Array(state.selectedUserIDs) : [],
                    expiresAt: state.isExpiryEnabled ? state.expiresAt : nil
                )
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.createResponse(try await apiResult {
                        try await filesClient.createShareLink(serverURL, request)
                    }), animation: .default)
                }

            case let .createResponse(.success(created)):
                state.isCreating = false
                state.createdShare = created
                state.$shareLinksRevision.withLock { $0 += 1 }
                return .none

            case let .createResponse(.failure(error)):
                state.isCreating = false
                state.errorMessage = error.userMessage
                return .none
            }
        }
    }
}
