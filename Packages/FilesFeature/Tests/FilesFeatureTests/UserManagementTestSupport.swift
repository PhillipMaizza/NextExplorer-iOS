import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import TestUtils
import Testing

enum UserManagementCall: Equatable, Sendable {
    case updateUser(id: String, request: UpdateUserRequest)
    case deleteUser(id: String)
    case createUser(CreateUserRequest)
    case setPassword(userID: String, password: String)
    case addVolume(userID: String, request: AddUserVolumeRequest)
    case updateVolume(userID: String, volumeID: String, label: String?, mode: ShareAccessMode)
    case removeVolume(userID: String, volumeID: String)
}

@MainActor
protocol UserManagementTestSupport {
    var calls: LockIsolated<[UserManagementCall]> { get }
    var listCalls: LockIsolated<Int> { get }
    var featureCalls: LockIsolated<Int> { get }
    var volumeLoads: LockIsolated<[String]> { get }
}

extension UserManagementTestSupport {
    typealias Store = TestStoreOf<UserManagementFeature>
    typealias State = UserManagementFeature.State

    typealias Call = UserManagementCall

    var serverURL: URL { SettingsTestSupport.serverURL }

    var projects: UserVolume { UserVolume(id: TestETag.first, userId: "2", label: "Projects", path: "/srv/projects", accessMode: .readwrite) }
    var media: UserVolume { UserVolume(id: "v9", userId: "2", label: TestFolder.media, path: "/srv/media", accessMode: .readonly) }

    func makeUser(id: String, admin: Bool = false, password: Bool = true, oidc: Bool = false) -> User {
        var methods: [AuthMethod] = []
        if password {
            methods.append(AuthMethod(method: "local_password"))
        }
        if oidc {
            methods.append(AuthMethod(method: "oidc", provider: "Authentik"))
        }
        return User(
            id: id,
            username: "user\(id)",
            email: "user\(id)@example.com",
            displayName: "User \(id)",
            roles: admin ? ["admin"] : [],
            authMethods: methods
        )
    }

    /// A list that already loaded, optionally with a user's detail open and its form seeded the way `userTapped` does.
    func loadedState(
        _ users: [User],
        detail: String? = nil,
        isVolumesEnabled: Bool = false,
        volumes: [UserVolume]? = nil
    ) -> State {
        var state = State(serverURL: serverURL, currentUserID: "me")
        state.users = IdentifiedArray(uniqueElements: users)
        state.phase = .loaded
        state.hasLoadedFeatures = true
        state.isUserVolumesEnabled = isVolumesEnabled
        if let detail, let user = state.users[id: detail] {
            state.detailUserID = detail
            state.editDisplayName = user.displayName ?? ""
            state.editUsername = user.username
            state.editEmail = user.email ?? ""
        }
        if let volumes {
            state.volumes = IdentifiedArray(uniqueElements: volumes)
            state.volumesPhase = .loaded
        }
        return state
    }

    func makeStore(
        _ state: State,
        users: @escaping @Sendable () async throws -> [User] = { throw FilesClientError.offline },
        features: @escaping @Sendable () async throws -> ServerFeatures = { throw FilesClientError.offline },
        volumes: @escaping @Sendable (String) async throws -> [UserVolume] = { _ in throw FilesClientError.offline },
        updateUser: @escaping @Sendable () async throws -> User = { throw FilesClientError.offline },
        deleteUser: @escaping @Sendable () async throws -> Void = { throw FilesClientError.offline },
        createUser: @escaping @Sendable () async throws -> User = { throw FilesClientError.offline },
        setPassword: @escaping @Sendable () async throws -> Void = { throw FilesClientError.offline },
        addVolume: @escaping @Sendable () async throws -> UserVolume = { throw FilesClientError.offline },
        updateVolume: @escaping @Sendable () async throws -> UserVolume = { throw FilesClientError.offline },
        removeVolume: @escaping @Sendable (String) async throws -> Void = { _ in throw FilesClientError.offline }
    ) -> Store {
        let calls = calls
        let listCalls = listCalls
        let featureCalls = featureCalls
        let volumeLoads = volumeLoads
        return TestStore(initialState: state) {
            UserManagementFeature()
        } withDependencies: {
            $0.filesClient.listUsers = { _ in
                listCalls.withValue { $0 += 1 }
                return try await users()
            }
            $0.filesClient.serverFeatures = { _ in
                featureCalls.withValue { $0 += 1 }
                return try await features()
            }
            $0.filesClient.userVolumes = { _, userID in
                volumeLoads.withValue { $0.append(userID) }
                return try await volumes(userID)
            }
            $0.filesClient.updateUser = { _, id, request in
                calls.withValue { $0.append(.updateUser(id: id, request: request)) }
                return try await updateUser()
            }
            $0.filesClient.deleteUser = { _, id in
                calls.withValue { $0.append(.deleteUser(id: id)) }
                try await deleteUser()
            }
            $0.filesClient.createUser = { _, request in
                calls.withValue { $0.append(.createUser(request)) }
                return try await createUser()
            }
            $0.filesClient.setUserPassword = { _, userID, password in
                calls.withValue { $0.append(.setPassword(userID: userID, password: password)) }
                try await setPassword()
            }
            $0.filesClient.addUserVolume = { _, userID, request in
                calls.withValue { $0.append(.addVolume(userID: userID, request: request)) }
                return try await addVolume()
            }
            $0.filesClient.updateUserVolume = { _, userID, volumeID, label, mode in
                calls.withValue { $0.append(.updateVolume(userID: userID, volumeID: volumeID, label: label, mode: mode)) }
                return try await updateVolume()
            }
            $0.filesClient.removeUserVolume = { _, userID, volumeID in
                try await removeVolume(volumeID)
                calls.withValue { $0.append(.removeVolume(userID: userID, volumeID: volumeID)) }
            }
        }
    }
}
