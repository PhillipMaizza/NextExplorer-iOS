import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import TestUtils
import Testing

@MainActor
struct UserManagementFeatureTests {
    private typealias Store = TestStoreOf<UserManagementFeature>
    private typealias State = UserManagementFeature.State

    enum Call: Equatable, Sendable {
        case updateUser(id: String, request: UpdateUserRequest)
        case deleteUser(id: String)
        case createUser(CreateUserRequest)
        case setPassword(userID: String, password: String)
        case addVolume(userID: String, request: AddUserVolumeRequest)
        case updateVolume(userID: String, volumeID: String, label: String?, mode: ShareAccessMode)
        case removeVolume(userID: String, volumeID: String)
    }

    private let serverURL = SettingsTestSupport.serverURL
    private let calls = LockIsolated<[Call]>([])
    private let listCalls = LockIsolated(0)
    private let featureCalls = LockIsolated(0)
    private let volumeLoads = LockIsolated<[String]>([])

    private let projects = UserVolume(id: "v1", userId: "2", label: "Projects", path: "/srv/projects", accessMode: .readwrite)
    private let media = UserVolume(id: "v9", userId: "2", label: "Media", path: "/srv/media", accessMode: .readonly)

    private func makeUser(id: String, admin: Bool = false, password: Bool = true, oidc: Bool = false) -> User {
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
    private func loadedState(
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

    private func makeStore(
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

    // MARK: Load

    @Test
    func onAppearLoadsUsersThenTheFeatureFlags() async {
        let users = [makeUser(id: "1", admin: true), makeUser(id: "2")]
        let store = makeStore(
            State(serverURL: serverURL, currentUserID: "me"),
            users: { users },
            features: { ServerFeatures(isUserVolumesEnabled: true) }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.usersResponse.success) {
            $0.phase = .loaded
            $0.users = IdentifiedArray(uniqueElements: users)
        }
        await store.receive(\.featuresResponse) {
            $0.hasLoadedFeatures = true
            $0.isUserVolumesEnabled = true
        }
    }

    @Test
    func onAppearSurfacesALoadFailureAndStillAsksForTheFeatureFlags() async {
        let store = makeStore(
            State(serverURL: serverURL, currentUserID: "me"),
            users: { throw FilesClientError.server(statusCode: 403) },
            features: { ServerFeatures() }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.usersResponse.failure) { $0.phase = .failed(L10n.Error.server(403)) }
        await store.receive(\.featuresResponse) { $0.hasLoadedFeatures = true }
    }

    @Test
    func aFailedFeatureFlagLoadNeverBlocksTheList() async {
        let users = [makeUser(id: "1")]
        let store = makeStore(
            State(serverURL: serverURL, currentUserID: "me"),
            users: { users },
            features: { throw FilesClientError.offline }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.usersResponse.success) {
            $0.phase = .loaded
            $0.users = IdentifiedArray(uniqueElements: users)
        }
        await store.finish()
        #expect(!store.state.hasLoadedFeatures)
        #expect(featureCalls.value == 1)
    }

    @Test
    func aServerAnswerWithDuplicateIdsKeepsTheFirstOfEach() async {
        let first = makeUser(id: "1")
        let duplicate = User(id: "1", username: "other", email: "other@example.com", roles: [])
        let store = makeStore(
            State(serverURL: serverURL, currentUserID: "me"),
            users: { [first, duplicate] },
            features: { ServerFeatures() }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.usersResponse.success) {
            $0.phase = .loaded
            $0.users = [first]
        }
        await store.receive(\.featuresResponse) { $0.hasLoadedFeatures = true }
    }

    @Test
    func onAppearDoesNothingOnceUsersAreLoaded() async {
        let store = makeStore(loadedState([makeUser(id: "1")]), users: { [] }, features: { ServerFeatures() })

        await store.send(.onAppear)
        #expect(listCalls.value == 0)
    }

    @Test
    func refreshingKeepsTheListVisibleAndReplacesItsUsers() async {
        let refreshed = [makeUser(id: "1"), makeUser(id: "3")]
        let store = makeStore(loadedState([makeUser(id: "1")]), users: { refreshed }, features: { ServerFeatures() })

        await store.send(.refreshRequested)
        await store.receive(\.usersResponse.success) { $0.users = IdentifiedArray(uniqueElements: refreshed) }
        await store.receive(\.featuresResponse)
    }

    @Test
    func aReloadThatDropsTheOpenUserClosesTheDetail() async {
        let remaining = [makeUser(id: "1", admin: true)]
        let store = makeStore(
            loadedState([makeUser(id: "1", admin: true), makeUser(id: "2")], detail: "2"),
            users: { remaining },
            features: { ServerFeatures() }
        )

        await store.send(.refreshRequested)
        await store.receive(\.usersResponse.success) {
            $0.users = IdentifiedArray(uniqueElements: remaining)
            $0.detailUserID = nil
        }
        await store.receive(\.featuresResponse)
    }

    @Test
    func aReloadDoesNotStompUnsavedProfileEdits() async {
        let user = makeUser(id: "2")
        let store = makeStore(loadedState([user], detail: "2"), users: { [user] }, features: { ServerFeatures() })

        await store.send(.editDisplayNameChanged("Half-typed name")) { $0.editDisplayName = "Half-typed name" }
        await store.send(.refreshRequested)
        await store.receive(\.usersResponse.success)
        await store.receive(\.featuresResponse)
        #expect(store.state.editDisplayName == "Half-typed name")
    }

    // MARK: Detail

    @Test
    func tappingAUserOpensDetailAndSeedsTheProfileForm() async {
        var state = loadedState([makeUser(id: "2")])
        state.detailTab = .security
        state.detailErrorMessage = "old"
        let store = makeStore(state)

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.detailTab = .profile
            $0.detailErrorMessage = nil
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
        }
        #expect(volumeLoads.value.isEmpty)
        #expect(featureCalls.value == 0)
    }

    @Test
    func tappingAnUnknownUserDoesNothing() async {
        let store = makeStore(loadedState([makeUser(id: "2")]))

        await store.send(.userTapped("404"))
    }

    @Test
    func openingDetailRetriesAFailedFeatureFlagLoad() async {
        var state = loadedState([makeUser(id: "2")])
        state.hasLoadedFeatures = false
        let store = makeStore(state, features: { ServerFeatures(isUserVolumesEnabled: true) })

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
        }
        await store.receive(\.featuresResponse) {
            $0.hasLoadedFeatures = true
            $0.isUserVolumesEnabled = true
        }
        #expect(featureCalls.value == 1)
    }

    @Test
    func openingDetailLoadsVolumesWhenTheFeatureIsOn() async {
        let store = makeStore(loadedState([makeUser(id: "2")], isVolumesEnabled: true), volumes: { [projects] _ in [projects] })

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
            $0.volumesPhase = .loading
        }
        await store.receive(\.volumesResponse.success) {
            $0.volumesPhase = .loaded
            $0.volumes = [projects]
        }
        #expect(volumeLoads.value == ["2"])
    }

    @Test
    func aVolumesLoadFailureIsShownInTheDetailBanner() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true),
            volumes: { _ in throw FilesClientError.server(statusCode: 500) }
        )

        await store.send(.detailTabChanged(.volumes)) {
            $0.detailTab = .volumes
            $0.volumesPhase = .loading
        }
        await store.receive(\.volumesResponse.failure) {
            $0.volumesPhase = .failed(L10n.Error.server(500))
            $0.detailErrorMessage = L10n.Error.server(500)
        }
    }

    @Test
    func theVolumesTabLoadsLazilyOnlyWhenNothingIsLoaded() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true),
            volumes: { [projects] _ in [projects] }
        )

        await store.send(.detailTabChanged(.security)) { $0.detailTab = .security }
        #expect(volumeLoads.value.isEmpty)

        await store.send(.detailTabChanged(.volumes)) {
            $0.detailTab = .volumes
            $0.volumesPhase = .loading
        }
        await store.receive(\.volumesResponse.success) {
            $0.volumesPhase = .loaded
            $0.volumes = [projects]
        }

        await store.send(.detailTabChanged(.security)) { $0.detailTab = .security }
        await store.send(.detailTabChanged(.volumes)) { $0.detailTab = .volumes }
        #expect(volumeLoads.value == ["2"])
    }

    @Test
    func theVolumesTabNeverLoadsWhenTheFeatureIsOff() async {
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2"), volumes: { _ in [] })

        await store.send(.detailTabChanged(.volumes)) { $0.detailTab = .volumes }
        #expect(volumeLoads.value.isEmpty)
    }

    @Test
    func dismissingTheDetailDropsAVolumesLoadStillInFlight() async {
        let gate = AsyncGate()
        let store = makeStore(
            loadedState([makeUser(id: "2")], isVolumesEnabled: true),
            volumes: { [projects] _ in
                try await gate.wait()
                return [projects]
            }
        )

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
            $0.volumesPhase = .loading
        }
        await store.send(.detailDismissed) {
            $0.detailUserID = nil
            $0.volumesPhase = .idle
        }
        await store.finish()
        #expect(store.state.volumes.isEmpty)
    }

    @Test
    func dismissingTheDetailDropsAProfileSaveStillInFlight() async {
        let gate = AsyncGate()
        let unchanged = makeUser(id: "2")
        let store = makeStore(loadedState([unchanged], detail: "2"), updateUser: {
            try await gate.wait()
            return unchanged
        })

        await store.send(.editDisplayNameChanged("Renamed")) { $0.editDisplayName = "Renamed" }
        await store.send(.saveProfileTapped) { $0.isSavingProfile = true }
        await store.send(.detailDismissed) {
            $0.detailUserID = nil
            $0.isSavingProfile = false
        }
        await store.finish()
        #expect(store.state.toast == nil)
    }

    @Test
    func dismissingTheDetailDropsAPendingGrantAdminConfirmation() async {
        let user = makeUser(id: "2")
        let store = makeStore(loadedState([user], detail: "2"))

        await store.send(.grantAdminTapped) { $0.userToGrantAdmin = user }
        await store.send(.detailDismissed) {
            $0.detailUserID = nil
            $0.userToGrantAdmin = nil
        }
    }

    @Test
    func theOwnAccountIsRecognisedByItsId() async {
        let me = makeUser(id: "me")
        let store = makeStore(loadedState([me, makeUser(id: "2")]))

        await store.send(.userTapped("me")) {
            $0.detailUserID = "me"
            $0.editDisplayName = "User me"
            $0.editUsername = "userme"
            $0.editEmail = "userme@example.com"
        }
        #expect(store.state.isViewingOwnAccount)
        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
        }
        #expect(!store.state.isViewingOwnAccount)
    }

    // MARK: Profile

    @Test
    func savingTheProfileSendsTheTrimmedFieldsThenUpdatesTheUserAndToasts() async {
        let user = makeUser(id: "2")
        let updated = User(id: "2", username: "user2", email: "new@example.com", displayName: "Renamed", roles: [], authMethods: user.authMethods)
        let store = makeStore(loadedState([user], detail: "2"), updateUser: { updated })

        await store.send(.editDisplayNameChanged("  Renamed  ")) { $0.editDisplayName = "  Renamed  " }
        await store.send(.editEmailChanged(" new@example.com ")) { $0.editEmail = " new@example.com " }
        await store.send(.saveProfileTapped) { $0.isSavingProfile = true }
        await store.receive(\.profileResponse.success) {
            $0.isSavingProfile = false
            $0.users[id: "2"] = updated
            $0.editDisplayName = "Renamed"
            $0.editEmail = "new@example.com"
            $0.toast = L10n.UserManagement.toastProfileUpdated
        }
        #expect(calls.value == [.updateUser(id: "2", request: UpdateUserRequest(email: "new@example.com", username: "user2", displayName: "Renamed"))])
        #expect(!store.state.isProfileDirty)
    }

    @Test
    func aProfileSaveFailureShowsTheServerMessageAndKeepsTheEdits() async {
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2"), updateUser: {
            throw FilesClientError.serverMessage(statusCode: 409, message: "Email already in use.")
        })

        await store.send(.editEmailChanged("dupe@example.com")) { $0.editEmail = "dupe@example.com" }
        await store.send(.saveProfileTapped) { $0.isSavingProfile = true }
        await store.receive(\.profileResponse.failure) {
            $0.isSavingProfile = false
            $0.detailErrorMessage = "Email already in use."
        }
        #expect(store.state.editEmail == "dupe@example.com")
    }

    struct ProfileEditCase: Sendable {
        let username: String
        let email: String
        let usernameError: String?
        let emailError: String?
        let isSaveEnabled: Bool
    }

    @Test(
        "A profile save needs a username and a well shaped email",
        arguments: [
            ProfileEditCase(username: "renamed", email: "user2@example.com", usernameError: nil, emailError: nil, isSaveEnabled: true),
            ProfileEditCase(
                username: "   ", email: "user2@example.com",
                usernameError: L10n.UserManagement.errorUsernameRequired, emailError: nil, isSaveEnabled: false
            ),
            ProfileEditCase(
                username: "user2", email: "",
                usernameError: nil, emailError: L10n.UserManagement.errorEmailRequired, isSaveEnabled: false
            ),
            ProfileEditCase(
                username: "user2", email: "broken@",
                usernameError: nil, emailError: L10n.UserManagement.errorEmailInvalid, isSaveEnabled: false
            ),
            ProfileEditCase(username: "user2", email: "user2@example.com", usernameError: nil, emailError: nil, isSaveEnabled: false),
        ]
    )
    func profileValidationGatesTheSave(_ testCase: ProfileEditCase) async {
        let unchanged = makeUser(id: "2")
        let store = makeStore(loadedState([unchanged], detail: "2"), updateUser: { unchanged })

        if testCase.username != "user2" {
            await store.send(.editUsernameChanged(testCase.username)) { $0.editUsername = testCase.username }
        }
        if testCase.email != "user2@example.com" {
            await store.send(.editEmailChanged(testCase.email)) { $0.editEmail = testCase.email }
        }

        #expect(store.state.profileUsernameError == testCase.usernameError)
        #expect(store.state.profileEmailError == testCase.emailError)
        #expect(store.state.isProfileSaveEnabled == testCase.isSaveEnabled)
        if !testCase.isSaveEnabled {
            await store.send(.saveProfileTapped)
            #expect(calls.value.isEmpty)
        }
    }

    // MARK: Roles

    @Test
    func grantingAdminAsksFirstThenSendsTheRolesAndToasts() async {
        let user = makeUser(id: "2")
        let promoted = User(id: "2", username: "user2", email: "user2@example.com", displayName: "User 2", roles: ["admin"], authMethods: user.authMethods)
        let store = makeStore(loadedState([user], detail: "2"), updateUser: { promoted })

        await store.send(.grantAdminTapped) { $0.userToGrantAdmin = user }
        #expect(calls.value.isEmpty)
        await store.send(.grantAdminConfirmed) {
            $0.userToGrantAdmin = nil
            $0.isUpdatingRoles = true
        }
        await store.receive(\.rolesResponse.success) {
            $0.isUpdatingRoles = false
            $0.users[id: "2"] = promoted
            $0.toast = L10n.UserManagement.toastAdminGranted
        }
        #expect(calls.value == [.updateUser(id: "2", request: UpdateUserRequest(roles: ["admin"]))])
    }

    @Test
    func grantingAdminKeepsTheUsersOtherRolesSorted() async {
        let editor = User(id: "2", username: "user2", email: "user2@example.com", roles: ["viewer", "editor"])
        let promoted = User(id: "2", username: "user2", email: "user2@example.com", roles: ["admin", "editor", "viewer"])
        let store = makeStore(loadedState([editor], detail: "2"), updateUser: { promoted })

        await store.send(.grantAdminTapped) { $0.userToGrantAdmin = editor }
        await store.send(.grantAdminConfirmed) {
            $0.userToGrantAdmin = nil
            $0.isUpdatingRoles = true
        }
        await store.receive(\.rolesResponse.success) {
            $0.isUpdatingRoles = false
            $0.users[id: "2"] = promoted
            $0.toast = L10n.UserManagement.toastAdminGranted
        }
        #expect(calls.value == [.updateUser(id: "2", request: UpdateUserRequest(roles: ["admin", "editor", "viewer"]))])
    }

    @Test
    func cancellingTheGrantAdminConfirmationLeavesTheUserUntouched() async {
        let user = makeUser(id: "2")
        let store = makeStore(loadedState([user], detail: "2"), updateUser: { user })

        await store.send(.grantAdminTapped) { $0.userToGrantAdmin = user }
        await store.send(.grantAdminCancelled) { $0.userToGrantAdmin = nil }
        await store.send(.grantAdminConfirmed)
        #expect(calls.value.isEmpty)
    }

    @Test
    func grantingAdminIsANoOpForAUserWhoIsAlreadyAdmin() async {
        let store = makeStore(loadedState([makeUser(id: "2", admin: true)], detail: "2"))

        await store.send(.grantAdminTapped)
        #expect(calls.value.isEmpty)
    }

    @Test
    func grantingAdminIsIgnoredWhileARoleUpdateIsRunning() async {
        var state = loadedState([makeUser(id: "2")], detail: "2")
        state.isUpdatingRoles = true
        let store = makeStore(state)

        await store.send(.grantAdminTapped)
        #expect(calls.value.isEmpty)
    }

    @Test
    func aGrantAdminServerFailureIsSurfacedInTheDetailBanner() async {
        let user = makeUser(id: "2")
        let store = makeStore(loadedState([user], detail: "2"), updateUser: {
            throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required.")
        })

        await store.send(.grantAdminTapped) { $0.userToGrantAdmin = user }
        await store.send(.grantAdminConfirmed) {
            $0.userToGrantAdmin = nil
            $0.isUpdatingRoles = true
        }
        await store.receive(\.rolesResponse.failure) {
            $0.isUpdatingRoles = false
            $0.detailErrorMessage = "Admin access required."
        }
    }

    // MARK: Delete

    @Test
    func deletingAUserRemovesItFromTheListAndClosesItsDetail() async {
        let user = makeUser(id: "2")
        let store = makeStore(loadedState([makeUser(id: "1", admin: true), user], detail: "2"), deleteUser: {})

        await store.send(.deleteUserTapped(user)) { $0.userToDelete = user }
        await store.send(.deleteUserConfirmed) { $0.userToDelete = nil }
        await store.receive(\.deleteUserResponse) {
            $0.users.remove(id: "2")
            $0.detailUserID = nil
            $0.toast = L10n.UserManagement.toastUserRemoved
        }
        #expect(calls.value == [.deleteUser(id: "2")])
    }

    @Test
    func deletingAnotherUserKeepsTheOpenDetail() async {
        let other = makeUser(id: "3")
        let store = makeStore(loadedState([makeUser(id: "2"), other], detail: "2"), deleteUser: {})

        await store.send(.deleteUserTapped(other)) { $0.userToDelete = other }
        await store.send(.deleteUserConfirmed) { $0.userToDelete = nil }
        await store.receive(\.deleteUserResponse) {
            $0.users.remove(id: "3")
            $0.toast = L10n.UserManagement.toastUserRemoved
        }
        #expect(store.state.detailUserID == "2")
    }

    @Test
    func cancellingADeleteLeavesTheListAlone() async {
        let user = makeUser(id: "2")
        let store = makeStore(loadedState([user]), deleteUser: {})

        await store.send(.deleteUserTapped(user)) { $0.userToDelete = user }
        await store.send(.deleteUserCancelled) { $0.userToDelete = nil }
        await store.send(.deleteUserConfirmed)
        #expect(calls.value.isEmpty)
    }

    @Test
    func aLastAdminDeleteFailureIsSurfacedInTheDetailBanner() async {
        let admin = makeUser(id: "1", admin: true)
        let store = makeStore(loadedState([admin], detail: "1"), deleteUser: {
            throw FilesClientError.serverMessage(statusCode: 400, message: "Cannot remove the last admin.")
        })

        await store.send(.deleteUserTapped(admin)) { $0.userToDelete = admin }
        await store.send(.deleteUserConfirmed) { $0.userToDelete = nil }
        await store.receive(\.deleteUserResponse) { $0.detailErrorMessage = "Cannot remove the last admin." }
        #expect(store.state.users[id: "1"] == admin)
        #expect(store.state.phase.errorMessage == nil)
    }

    // MARK: Create

    @Test
    func creatingAUserSendsTheTrimmedRequestAndAppendsItToTheList() async {
        let created = makeUser(id: "9")
        let store = makeStore(loadedState([makeUser(id: "1", admin: true)]), createUser: { created })

        await store.send(.createUserTapped) { $0.createSheet = .init() }
        await store.send(.createEmailChanged("new@example.com")) { $0.createSheet?.email = "new@example.com" }
        await store.send(.createUsernameChanged("  newbie  ")) { $0.createSheet?.username = "  newbie  " }
        await store.send(.createPasswordChanged("secret1")) { $0.createSheet?.password = "secret1" }
        await store.send(.createIsAdminChanged(true)) { $0.createSheet?.isAdmin = true }
        await store.send(.createSubmitTapped) { $0.createSheet?.isSubmitting = true }
        await store.receive(\.createResponse.success) {
            $0.createSheet = nil
            $0.users.append(created)
            $0.toast = L10n.UserManagement.toastUserCreated
        }
        #expect(calls.value == [.createUser(CreateUserRequest(email: "new@example.com", username: "newbie", password: "secret1", isAdmin: true))])
    }

    @Test(
        "A blank username is sent as no username",
        arguments: ["", "   "]
    )
    func aBlankUsernameIsOmitted(_ username: String) async {
        let created = makeUser(id: "9")
        let store = makeStore(loadedState([]), createUser: { created })

        await store.send(.createUserTapped) { $0.createSheet = .init() }
        await store.send(.createEmailChanged("new@example.com")) { $0.createSheet?.email = "new@example.com" }
        if !username.isEmpty {
            await store.send(.createUsernameChanged(username)) { $0.createSheet?.username = username }
        }
        await store.send(.createPasswordChanged("secret1")) { $0.createSheet?.password = "secret1" }
        await store.send(.createSubmitTapped) { $0.createSheet?.isSubmitting = true }
        await store.receive(\.createResponse.success) {
            $0.createSheet = nil
            $0.users.append(created)
            $0.toast = L10n.UserManagement.toastUserCreated
        }
        #expect(calls.value == [.createUser(CreateUserRequest(email: "new@example.com", username: nil, password: "secret1", isAdmin: false))])
    }

    struct CreateCase: Sendable {
        let email: String
        let password: String
        let emailError: String?
        let passwordError: String?
        let isSubmitEnabled: Bool
    }

    @Test(
        "Create needs a well shaped email and a six character password, with inline errors once typed",
        arguments: [
            CreateCase(email: "x@y.z", password: "123456", emailError: nil, passwordError: nil, isSubmitEnabled: true),
            CreateCase(email: "x@y.z", password: "12345", emailError: nil, passwordError: L10n.UserManagement.errorPasswordTooShort(6), isSubmitEnabled: false),
            CreateCase(email: "not-an-email", password: "longenough", emailError: L10n.UserManagement.errorEmailInvalid, passwordError: nil, isSubmitEnabled: false),
            CreateCase(email: "", password: "longenough", emailError: nil, passwordError: nil, isSubmitEnabled: false),
            CreateCase(email: "x@y.z", password: "", emailError: nil, passwordError: nil, isSubmitEnabled: false),
        ]
    )
    func createValidation(_ testCase: CreateCase) {
        let sheet = UserManagementFeature.CreateUserState(email: testCase.email, password: testCase.password)

        #expect(sheet.emailError == testCase.emailError)
        #expect(sheet.passwordError == testCase.passwordError)
        #expect(sheet.isSubmitEnabled == testCase.isSubmitEnabled)
    }

    @Test
    func aCreateWhileSubmittingIsNotEnabled() {
        let sheet = UserManagementFeature.CreateUserState(email: "x@y.z", password: "123456", isSubmitting: true)

        #expect(!sheet.isSubmitEnabled)
    }

    @Test
    func submittingAnInvalidCreateFormDoesNothing() async {
        var state = loadedState([])
        state.createSheet = .init(email: "not-an-email", password: "longenough")
        let store = makeStore(state)

        await store.send(.createSubmitTapped)
        #expect(calls.value.isEmpty)
    }

    @Test
    func aCreateUserFailureKeepsTheSheetOpenWithItsMessage() async {
        var state = loadedState([])
        state.createSheet = .init(email: "dupe@example.com", password: "longenough")
        let store = makeStore(state, createUser: {
            throw FilesClientError.serverMessage(statusCode: 409, message: "Email already in use.")
        })

        await store.send(.createSubmitTapped) { $0.createSheet?.isSubmitting = true }
        await store.receive(\.createResponse.failure) {
            $0.createSheet?.isSubmitting = false
            $0.createSheet?.errorMessage = "Email already in use."
        }
        #expect(store.state.users.isEmpty)
    }

    @Test
    func dismissingTheCreateSheetDropsIt() async {
        var state = loadedState([])
        state.createSheet = .init(email: "x@y.z")
        let store = makeStore(state)

        await store.send(.createSheetDismissed) { $0.createSheet = nil }
    }

    // MARK: Password

    @Test
    func settingAPasswordSendsItToastsAndReloadsTheList() async {
        let user = makeUser(id: "2", password: false, oidc: true)
        let refreshed = [makeUser(id: "2", password: true, oidc: true)]
        let store = makeStore(loadedState([user], detail: "2"), users: { refreshed }, setPassword: {})

        await store.send(.setPasswordTapped) {
            $0.passwordSheet = .init(userID: "2", userLabel: "User 2", hasExistingPassword: false)
        }
        await store.send(.passwordFieldChanged("secret1")) { $0.passwordSheet?.password = "secret1" }
        await store.send(.passwordSubmitTapped) { $0.passwordSheet?.isSubmitting = true }
        await store.receive(\.passwordResponse.success) {
            $0.passwordSheet = nil
            $0.toast = L10n.UserManagement.toastPasswordUpdated
        }
        await store.receive(\.usersResponse.success) { $0.users = IdentifiedArray(uniqueElements: refreshed) }
        #expect(calls.value == [.setPassword(userID: "2", password: "secret1")])
        #expect(store.state.users[id: "2"]?.hasLocalPassword == true)
    }

    @Test
    func theSheetKnowsWhetherTheUserAlreadyHasAPassword() async {
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2"))

        await store.send(.setPasswordTapped) {
            $0.passwordSheet = .init(userID: "2", userLabel: "User 2", hasExistingPassword: true)
        }
        await store.send(.passwordSheetDismissed) { $0.passwordSheet = nil }
    }

    @Test
    func aSetPasswordFailureKeepsTheSheetOpenWithItsMessage() async {
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2"), setPassword: {
            throw FilesClientError.serverMessage(statusCode: 400, message: "Password must be at least 6 characters long.")
        })

        await store.send(.setPasswordTapped) {
            $0.passwordSheet = .init(userID: "2", userLabel: "User 2", hasExistingPassword: true)
        }
        await store.send(.passwordFieldChanged("secret1")) { $0.passwordSheet?.password = "secret1" }
        await store.send(.passwordSubmitTapped) { $0.passwordSheet?.isSubmitting = true }
        await store.receive(\.passwordResponse.failure) {
            $0.passwordSheet?.isSubmitting = false
            $0.passwordSheet?.errorMessage = "Password must be at least 6 characters long."
        }
        #expect(store.state.passwordSheet?.password == "secret1")
    }

    @Test(
        "The password sheet needs six characters",
        arguments: [
            ("", nil, false),
            ("12345", L10n.UserManagement.errorPasswordTooShort(6), false),
            ("123456", nil, true),
        ] as [(String, String?, Bool)]
    )
    func passwordSheetValidation(password: String, error: String?, isSubmitEnabled: Bool) {
        let sheet = UserManagementFeature.PasswordSheetState(userID: "2", userLabel: "User 2", hasExistingPassword: true, password: password)

        #expect(sheet.passwordError == error)
        #expect(sheet.isSubmitEnabled == isSubmitEnabled)
    }

    @Test
    func submittingAShortPasswordDoesNothing() async {
        var state = loadedState([makeUser(id: "2")], detail: "2")
        state.passwordSheet = .init(userID: "2", userLabel: "User 2", hasExistingPassword: true, password: "12345")
        let store = makeStore(state)

        await store.send(.passwordSubmitTapped)
        #expect(calls.value.isEmpty)
    }

    // MARK: Volumes

    @Test
    func assigningAVolumeSendsTheRequestAndAddsItToTheDetail() async {
        let created = media
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: []), addVolume: { created })

        await store.send(.addVolumeTapped) { $0.volumeSheet = .init(userID: "2") }
        await store.send(.volumePathSelected("/srv/media")) {
            $0.volumeSheet?.selectedPath = "/srv/media"
            $0.volumeSheet?.label = "media"
        }
        await store.send(.volumeLabelChanged("Media")) { $0.volumeSheet?.label = "Media" }
        await store.send(.volumeAccessModeChanged(.readonly)) { $0.volumeSheet?.accessMode = .readonly }
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse.success) {
            $0.volumeSheet = nil
            $0.volumes[id: "v9"] = created
            $0.toast = L10n.UserManagement.toastVolumeSaved
        }
        #expect(calls.value == [.addVolume(userID: "2", request: AddUserVolumeRequest(label: "Media", path: "/srv/media", accessMode: .readonly))])
    }

    @Test
    func pickingAPathKeepsALabelTheAdminAlreadyTyped() async {
        var state = loadedState([makeUser(id: "2")], detail: "2")
        state.volumeSheet = .init(userID: "2", label: "Typed")
        let store = makeStore(state)

        await store.send(.volumePathSelected("/srv/media")) { $0.volumeSheet?.selectedPath = "/srv/media" }
        #expect(store.state.volumeSheet?.label == "Typed")
    }

    struct VolumeSheetCase: Sendable {
        let label: String
        let path: String
        let isSubmitting: Bool
        let isSubmitEnabled: Bool
    }

    @Test(
        "The volume sheet needs a label and a path and submits only once",
        arguments: [
            VolumeSheetCase(label: "Media", path: "/srv/media", isSubmitting: false, isSubmitEnabled: true),
            VolumeSheetCase(label: "  ", path: "/srv/media", isSubmitting: false, isSubmitEnabled: false),
            VolumeSheetCase(label: "Media", path: "  ", isSubmitting: false, isSubmitEnabled: false),
            VolumeSheetCase(label: "Media", path: "/srv/media", isSubmitting: true, isSubmitEnabled: false),
        ]
    )
    func volumeSheetValidation(_ testCase: VolumeSheetCase) async {
        var state = loadedState([makeUser(id: "2")], detail: "2")
        state.volumeSheet = .init(userID: "2", label: testCase.label, selectedPath: testCase.path, isSubmitting: testCase.isSubmitting)
        let store = makeStore(state, addVolume: { [media] in media })

        #expect(store.state.volumeSheet?.isSubmitEnabled == testCase.isSubmitEnabled)
        if !testCase.isSubmitEnabled {
            await store.send(.volumeSubmitTapped)
            #expect(calls.value.isEmpty)
        }
    }

    @Test
    func aVolumeSaveFailureKeepsTheSheetOpenWithItsMessage() async {
        let store = makeStore(loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: []), addVolume: {
            throw FilesClientError.serverMessage(statusCode: 409, message: "This path is already assigned to this user")
        })

        await store.send(.addVolumeTapped) { $0.volumeSheet = .init(userID: "2") }
        await store.send(.volumePathSelected("/srv/media")) {
            $0.volumeSheet?.selectedPath = "/srv/media"
            $0.volumeSheet?.label = "media"
        }
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse.failure) {
            $0.volumeSheet?.isSubmitting = false
            $0.volumeSheet?.errorMessage = "This path is already assigned to this user"
        }
        #expect(store.state.volumes.isEmpty)
    }

    @Test
    func editingAVolumeGoesThroughUpdateNotAdd() async {
        let saved = UserVolume(id: "v1", userId: "2", label: "Renamed", path: "/srv/projects", accessMode: .readonly)
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            updateVolume: { saved }
        )

        await store.send(.editVolumeTapped(projects)) {
            $0.volumeSheet = .init(userID: "2", editingVolumeID: "v1", label: "Projects", selectedPath: "/srv/projects", accessMode: .readwrite)
        }
        await store.send(.volumeLabelChanged("Renamed")) { $0.volumeSheet?.label = "Renamed" }
        await store.send(.volumeAccessModeChanged(.readonly)) { $0.volumeSheet?.accessMode = .readonly }
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse.success) {
            $0.volumeSheet = nil
            $0.volumes[id: "v1"] = saved
            $0.toast = L10n.UserManagement.toastVolumeSaved
        }
        #expect(calls.value == [.updateVolume(userID: "2", volumeID: "v1", label: "Renamed", mode: .readonly)])
    }

    @Test
    func dismissingTheVolumeSheetDropsIt() async {
        var state = loadedState([makeUser(id: "2")], detail: "2")
        state.volumeSheet = .init(userID: "2")
        let store = makeStore(state)

        await store.send(.volumeSheetDismissed) { $0.volumeSheet = nil }
    }

    @Test
    func removingAVolumeAsksFirstThenDropsItFromTheDetail() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            removeVolume: { _ in }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        #expect(calls.value.isEmpty)
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = ["v1"]
        }
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.volumes.remove(id: "v1")
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
        #expect(calls.value == [.removeVolume(userID: "2", volumeID: "v1")])
    }

    @Test
    func cancellingAVolumeRemovalDeletesNothing() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            removeVolume: { _ in }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeCancelled) { $0.volumeToRemove = nil }
        await store.send(.removeVolumeConfirmed)
        #expect(calls.value.isEmpty)
    }

    @Test
    func aRemoveVolumeFailureIsSurfacedAndKeepsTheVolume() async {
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            removeVolume: { _ in throw FilesClientError.server(statusCode: 500) }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = ["v1"]
        }
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.detailErrorMessage = L10n.Error.server(500)
        }
        #expect(store.state.volumes[id: "v1"] == projects)
    }

    @Test
    func removingAVolumeWhileASaveIsInFlightDoesNotCancelTheSave() async {
        let saveGate = AsyncGate()
        let created = media
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            addVolume: {
                try await saveGate.wait()
                return created
            },
            removeVolume: { _ in }
        )

        await store.send(.addVolumeTapped) { $0.volumeSheet = .init(userID: "2") }
        await store.send(.volumePathSelected("/srv/media")) {
            $0.volumeSheet?.selectedPath = "/srv/media"
            $0.volumeSheet?.label = "media"
        }
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = ["v1"]
        }
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.volumes.remove(id: "v1")
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
        saveGate.open()
        await store.receive(\.volumeResponse.success) {
            $0.volumeSheet = nil
            $0.volumes[id: "v9"] = created
            $0.toast = L10n.UserManagement.toastVolumeSaved
        }
    }

    @Test
    func twoDifferentVolumeRemovalsBothComplete() async {
        let second = UserVolume(id: "v2", userId: "2", label: "B", path: "/b", accessMode: .readwrite)
        let gates = ["v1": AsyncGate(), "v2": AsyncGate()]
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects, second]),
            removeVolume: { id in try await gates[id]?.wait() }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = ["v1"]
        }
        await store.send(.removeVolumeTapped(second)) { $0.volumeToRemove = second }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = ["v1", "v2"]
        }
        gates["v1"]?.open()
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = ["v2"]
            $0.volumes.remove(id: "v1")
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
        gates["v2"]?.open()
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.volumes.remove(id: "v2")
        }
        #expect(calls.value == [.removeVolume(userID: "2", volumeID: "v1"), .removeVolume(userID: "2", volumeID: "v2")])
    }

    @Test
    func confirmingTheSameVolumeRemovalTwiceRunsASingleDeleteThatIsNeverCancelled() async {
        let gate = AsyncGate()
        let store = makeStore(
            loadedState([makeUser(id: "2")], detail: "2", isVolumesEnabled: true, volumes: [projects]),
            removeVolume: { _ in try await gate.wait() }
        )

        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) {
            $0.volumeToRemove = nil
            $0.removingVolumeIDs = ["v1"]
        }
        await store.send(.removeVolumeTapped(projects)) { $0.volumeToRemove = projects }
        await store.send(.removeVolumeConfirmed) { $0.volumeToRemove = nil }
        gate.open()
        await store.receive(\.removeVolumeResponse) {
            $0.removingVolumeIDs = []
            $0.volumes.remove(id: "v1")
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
        #expect(calls.value == [.removeVolume(userID: "2", volumeID: "v1")])
    }

    // MARK: Toast

    @Test
    func dismissingTheToastClearsIt() async {
        var state = loadedState([])
        state.toast = "Saved"
        let store = makeStore(state)

        await store.send(.toastDismissed) { $0.toast = nil }
    }

    // MARK: Search

    @Test
    func searchFiltersByNameUsernameOrEmailIgnoringCase() async {
        let users = [
            makeUser(id: "1"),
            User(id: "2", username: "jrivera", email: "jamie@corp.com", displayName: "Jamie Rivera"),
            User(id: "3", username: "sokafor", email: "sam@corp.com", displayName: "Sam Okafor"),
        ]
        let store = makeStore(loadedState(users))

        await store.send(.searchQueryChanged("RIVERA")) { $0.searchQuery = "RIVERA" }
        #expect(store.state.displayedUsers.map(\.id) == ["2"])

        await store.send(.searchQueryChanged("sokafor")) { $0.searchQuery = "sokafor" }
        #expect(store.state.displayedUsers.map(\.id) == ["3"])

        await store.send(.searchQueryChanged("corp.com")) { $0.searchQuery = "corp.com" }
        #expect(store.state.displayedUsers.map(\.id) == ["2", "3"])
        #expect(!store.state.isSearchWithoutResults)

        await store.send(.searchQueryChanged("nobody")) { $0.searchQuery = "nobody" }
        #expect(store.state.displayedUsers.isEmpty)
        #expect(store.state.isSearchWithoutResults)

        await store.send(.searchQueryChanged("   ")) { $0.searchQuery = "   " }
        #expect(store.state.displayedUsers.count == 3)
        #expect(!store.state.isSearchWithoutResults)
    }

    // MARK: Sort

    @Test
    func theListSortsByTypeThenNameByDefaultAndFollowsTheSortSheet() async {
        let users = [
            User(id: "1", username: "amy", email: "zed@corp.com", displayName: "Amy"),
            User(id: "2", username: "mia", email: "bob@corp.com", displayName: "Mia", roles: ["admin"]),
            User(id: "3", username: "zoe", email: "amy@corp.com", displayName: "Zoe"),
        ]
        let store = makeStore(loadedState(users))

        #expect(store.state.displayedUsers.map(\.id) == ["2", "1", "3"])

        await store.send(.sortOptionChanged(.name)) { $0.sortOption = .name }
        #expect(store.state.displayedUsers.map(\.id) == ["1", "2", "3"])

        await store.send(.sortOptionChanged(.email)) { $0.sortOption = .email }
        #expect(store.state.displayedUsers.map(\.id) == ["3", "2", "1"])

        await store.send(.sortDirectionChanged(.descending)) { $0.sortDirection = .descending }
        #expect(store.state.displayedUsers.map(\.id) == ["1", "2", "3"])

        await store.send(.sortOptionChanged(.type)) { $0.sortOption = .type }
        #expect(store.state.displayedUsers.map(\.id) == ["3", "1", "2"])
    }

    @Test
    func usersWithTheSameNameSortByIdSoTheOrderIsStable() {
        var state = loadedState([
            User(id: "b", username: "same", email: nil, displayName: "Same"),
            User(id: "a", username: "same", email: nil, displayName: "Same"),
        ])
        state.sortOption = .name

        #expect(state.displayedUsers.map(\.id) == ["a", "b"])
    }
}
