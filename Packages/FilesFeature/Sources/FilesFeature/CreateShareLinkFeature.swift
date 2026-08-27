import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

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

        public var isCreating = false
        public var errorMessage: String?
        public var createdShare: CreatedShare?
        public var directLinkMode: DirectLinkMode = .auto

        /// Shareable-users list, loaded the first time "Specific users" is chosen.
        public var shareableUsers: IdentifiedArrayOf<User> = []
        public var selectedUserIDs: Set<User.ID> = []
        public var isLoadingUsers = false
        public var hasLoadedUsers = false
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

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
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
                guard target == .users, !state.hasLoadedUsers, !state.isLoadingUsers else { return .none }
                state.isLoadingUsers = true
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.shareableUsersResponse(await apiResult {
                        try await filesClient.shareableUsers(serverURL)
                    }))
                }

            case let .shareableUsersResponse(.success(users)):
                state.isLoadingUsers = false
                state.hasLoadedUsers = true
                state.shareableUsers = IdentifiedArray(uniqueElements: users)
                return .none

            case let .shareableUsersResponse(.failure(error)):
                state.isLoadingUsers = false
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
                return .none

            case let .expiresAtChanged(date):
                state.expiresAt = date
                return .none

            case let .directLinkModeChanged(mode):
                state.directLinkMode = mode
                return .none

            case .createTapped:
                guard state.isCreateEnabled else { return .none }
                if state.isExpiryEnabled, state.expiresAt <= date.now {
                    state.errorMessage = "Pick an expiration date in the future."
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
                    await send(.createResponse(await apiResult {
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
