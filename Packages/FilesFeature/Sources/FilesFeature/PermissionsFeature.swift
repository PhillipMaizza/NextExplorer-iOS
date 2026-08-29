import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// Drives the "Permissions" sheet (`PermissionsSheet`) for one file or folder — view the
/// POSIX mode / owner / group from `GET /api/permissions/*`, then chmod and chown via
/// `POST /api/permissions/{chmod,chown}`. Every successful write re-fetches so the grid
/// reflects what actually stuck (a recursive `chmod -R` is best-effort server side).
@Reducer
public struct PermissionsFeature {
    @ObservableState
    public struct State: Equatable, Identifiable, Sendable {
        public let serverURL: URL
        public let item: FileItem

        public var permissions: FilePermissions?
        public var isLoading = false
        public var loadError: String?

        /// Editable rights grid, seeded from `permissions` on each load.
        public var grid: [PermissionScope: Set<PermissionRight>] = [:]
        public var recursive = false
        public var ownerDraft = ""
        public var groupDraft = ""

        public var isSavingMode = false
        public var isSavingOwnership = false
        public var actionError: String?

        public var id: FileItem.ID { item.id }

        public init(serverURL: URL, item: FileItem) {
            self.serverURL = serverURL
            self.item = item
        }

        /// The grid as the 3-digit octal string `chmod` wants.
        public var octalString: String { FilePermissions.octalString(from: grid) }

        public var isModeDirty: Bool {
            guard let original = permissions?.octalString else { return false }
            return octalString != original
        }

        public var isOwnershipDirty: Bool {
            guard let permissions else { return false }
            let owner = ownerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = groupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return (!owner.isEmpty && owner != permissions.owner)
                || (!group.isEmpty && group != permissions.group)
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case permissionsResponse(Result<FilePermissions, FilesClientError>)
        case toggle(PermissionScope, PermissionRight)
        case recursiveChanged(Bool)
        case ownerDraftChanged(String)
        case groupDraftChanged(String)
        case applyModeTapped
        case modeResponse(Result<Bool, FilesClientError>)
        case applyOwnershipTapped
        case ownershipResponse(Result<Bool, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case load, chmod, chown }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                state.loadError = nil
                let serverURL = state.serverURL
                let path = state.item.id
                let filesClient = self.filesClient
                return .run { send in
                    await send(.permissionsResponse(await apiResult {
                        try await filesClient.fetchPermissions(serverURL, path)
                    }))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .permissionsResponse(.success(permissions)):
                state.isLoading = false
                state.permissions = permissions
                state.grid = permissions.grid
                state.recursive = false
                state.ownerDraft = permissions.owner
                state.groupDraft = permissions.group
                return .none

            case let .permissionsResponse(.failure(error)):
                state.isLoading = false
                state.loadError = error.userMessage
                return .none

            case let .toggle(scope, right):
                var rights = state.grid[scope] ?? []
                if rights.contains(right) { rights.remove(right) } else { rights.insert(right) }
                state.grid[scope] = rights
                state.actionError = nil
                return .none

            case let .recursiveChanged(value):
                state.recursive = value
                return .none

            case let .ownerDraftChanged(value):
                state.ownerDraft = value
                state.actionError = nil
                return .none

            case let .groupDraftChanged(value):
                state.groupDraft = value
                state.actionError = nil
                return .none

            case .applyModeTapped:
                guard state.isModeDirty, !state.isSavingMode else { return .none }
                state.isSavingMode = true
                state.actionError = nil
                let serverURL = state.serverURL
                let path = state.item.id
                let mode = state.octalString
                let recursive = state.recursive && state.item.isDirectory
                let filesClient = self.filesClient
                return .run { send in
                    await send(.modeResponse(await apiResult {
                        try await filesClient.changePermissions(serverURL, path, mode, recursive)
                        return true
                    }))
                }
                .cancellable(id: CancelID.chmod, cancelInFlight: true)

            case .modeResponse(.success):
                state.isSavingMode = false
                return .send(.onAppear)

            case let .modeResponse(.failure(error)):
                state.isSavingMode = false
                state.actionError = error.userMessage
                return .none

            case .applyOwnershipTapped:
                guard state.isOwnershipDirty, !state.isSavingOwnership,
                      let permissions = state.permissions else { return .none }
                state.isSavingOwnership = true
                state.actionError = nil
                let owner = state.ownerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                let group = state.groupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                let ownerArg = (owner.isEmpty || owner == permissions.owner) ? nil : owner
                let groupArg = (group.isEmpty || group == permissions.group) ? nil : group
                let serverURL = state.serverURL
                let path = state.item.id
                let filesClient = self.filesClient
                return .run { send in
                    await send(.ownershipResponse(await apiResult {
                        try await filesClient.changeOwnership(serverURL, path, ownerArg, groupArg)
                        return true
                    }))
                }
                .cancellable(id: CancelID.chown, cancelInFlight: true)

            case .ownershipResponse(.success):
                state.isSavingOwnership = false
                return .send(.onAppear)

            case let .ownershipResponse(.failure(error)):
                state.isSavingOwnership = false
                state.actionError = error.userMessage
                return .none
            }
        }
    }
}
