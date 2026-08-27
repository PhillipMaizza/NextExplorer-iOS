import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct UserManagementFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    private func makeUser(
        id: String,
        admin: Bool = false,
        password: Bool = true,
        oidc: Bool = false
    ) -> User {
        var methods: [AuthMethod] = []
        if password { methods.append(AuthMethod(method: "local_password")) }
        if oidc { methods.append(AuthMethod(method: "oidc", provider: "Authentik")) }
        return User(
            id: id,
            username: "user\(id)",
            email: "user\(id)@example.com",
            displayName: "User \(id)",
            roles: admin ? ["admin"] : [],
            authMethods: methods
        )
    }

    /// Every test drives `onAppear` first; the two loads (`listUsers`, `serverFeatures`) race,
    /// so the suite runs non exhaustive and asserts the mutations it cares about explicitly.
    private func bootedStore(
        users: [User],
        volumesEnabled: Bool = false,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) async -> TestStoreOf<UserManagementFeature> {
        let store = TestStore(
            initialState: UserManagementFeature.State(serverURL: serverURL, currentUserID: "me")
        ) {
            UserManagementFeature()
        } withDependencies: {
            $0.filesClient.listUsers = { _ in users }
            $0.filesClient.serverFeatures = { _ in ServerFeatures(isUserVolumesEnabled: volumesEnabled) }
            $0.filesClient.userVolumes = { _, _ in [] }
            configure(&$0)
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.usersResponse)
        return store
    }

    // MARK: Load

    @Test
    func onAppearLoadsUsersAndFeatures() async {
        let users = [makeUser(id: "1", admin: true), makeUser(id: "2")]
        let store = await bootedStore(users: users, volumesEnabled: true)
        await store.receive(\.featuresResponse)

        #expect(store.state.users.elements == users)
        #expect(store.state.isUserVolumesEnabled)
        #expect(!store.state.isLoading)
    }

    @Test
    func onAppearSurfacesALoadFailure() async {
        let store = await bootedStore(users: []) {
            $0.filesClient.listUsers = { _ in throw FilesClientError.server(statusCode: 403) }
        }
        #expect(store.state.errorMessage == FilesClientError.server(statusCode: 403).userMessage)
        #expect(!store.state.isLoading)
    }

    // MARK: Detail

    @Test
    func tappingAUserOpensDetailAndSeedsTheProfileForm() async {
        let store = await bootedStore(users: [makeUser(id: "2")])

        await store.send(.userTapped("2")) {
            $0.detailUserID = "2"
            $0.detailTab = .profile
            $0.editDisplayName = "User 2"
            $0.editUsername = "user2"
            $0.editEmail = "user2@example.com"
        }
    }

    @Test
    func openingDetailLoadsVolumesWhenTheFeatureIsOn() async {
        let volume = UserVolume(id: "v1", userId: "2", label: "Projects", path: "/srv/projects", accessMode: .readwrite)
        let store = await bootedStore(users: [makeUser(id: "2")], volumesEnabled: true) {
            $0.filesClient.userVolumes = { _, _ in [volume] }
        }

        await store.send(.userTapped("2")) { $0.isLoadingVolumes = true }
        await store.receive(\.volumesResponse) {
            $0.isLoadingVolumes = false
            $0.volumes = [volume]
        }
    }

    // MARK: Profile

    @Test
    func savingTheProfileUpdatesTheUserAndToasts() async {
        let user = makeUser(id: "2")
        let updated = User(id: "2", username: "user2", email: "new@example.com", displayName: "Renamed", roles: [], authMethods: user.authMethods)
        let store = await bootedStore(users: [user]) {
            $0.filesClient.updateUser = { _, _, _ in updated }
        }
        await store.send(.userTapped("2"))
        await store.send(.editDisplayNameChanged("Renamed"))
        await store.send(.editEmailChanged("new@example.com"))
        await store.send(.saveProfileTapped) { $0.isSavingProfile = true }
        await store.receive(\.profileResponse) {
            $0.isSavingProfile = false
            $0.users[id: "2"] = updated
            $0.toast = L10n.UserManagement.toastProfileUpdated
        }
    }

    @Test
    func aProfileSaveFailureShowsTheServerMessage() async {
        let store = await bootedStore(users: [makeUser(id: "2")]) {
            $0.filesClient.updateUser = { _, _, _ in
                throw FilesClientError.serverMessage(statusCode: 409, message: "Email already in use.")
            }
        }
        await store.send(.userTapped("2"))
        await store.send(.editEmailChanged("dupe@example.com"))
        await store.send(.saveProfileTapped)
        await store.receive(\.profileResponse) {
            $0.isSavingProfile = false
            $0.detailErrorMessage = "Email already in use."
        }
    }

    // MARK: Roles

    @Test
    func grantingAdminUpdatesRolesAndToasts() async {
        let user = makeUser(id: "2")
        let promoted = User(id: "2", username: "user2", email: "user2@example.com", displayName: "User 2", roles: ["admin"], authMethods: user.authMethods)
        let store = await bootedStore(users: [user]) {
            $0.filesClient.updateUser = { _, _, _ in promoted }
        }
        await store.send(.userTapped("2"))
        await store.send(.grantAdminTapped) { $0.isUpdatingRoles = true }
        await store.receive(\.rolesResponse) {
            $0.isUpdatingRoles = false
            $0.users[id: "2"] = promoted
            $0.toast = L10n.UserManagement.toastAdminGranted
        }
    }

    @Test
    func grantingAdminIsANoOpForAUserWhoIsAlreadyAdmin() async {
        let store = await bootedStore(users: [makeUser(id: "2", admin: true)]) {
            $0.filesClient.updateUser = { _, _, _ in Issue.record("must not call the server"); throw FilesClientError.network("x") }
        }
        await store.send(.userTapped("2"))
        await store.send(.grantAdminTapped)  // guarded, user is already an admin
        #expect(store.state.isUpdatingRoles == false)
    }

    @Test
    func aGrantAdminServerFailureIsSurfacedInTheDetailBanner() async {
        let store = await bootedStore(users: [makeUser(id: "2")]) {
            $0.filesClient.updateUser = { _, _, _ in
                throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required.")
            }
        }
        await store.send(.userTapped("2"))
        await store.send(.grantAdminTapped) { $0.isUpdatingRoles = true }
        await store.receive(\.rolesResponse) {
            $0.isUpdatingRoles = false
            $0.detailErrorMessage = "Admin access required."
        }
    }

    // MARK: Delete

    @Test
    func deletingAUserRemovesItFromTheList() async {
        let user = makeUser(id: "2")
        let store = await bootedStore(users: [makeUser(id: "1", admin: true), user]) {
            $0.filesClient.deleteUser = { _, _ in }
        }
        await store.send(.deleteUserTapped(user)) { $0.userToDelete = user }
        await store.send(.deleteUserConfirmed) { $0.userToDelete = nil }
        await store.receive(\.deleteUserResponse) {
            $0.users.remove(id: "2")
            $0.toast = L10n.UserManagement.toastUserRemoved
        }
    }

    @Test
    func aLastAdminDeleteFailureIsSurfacedInTheDetailBanner() async {
        let admin = makeUser(id: "1", admin: true)
        let store = await bootedStore(users: [admin]) {
            $0.filesClient.deleteUser = { _, _ in
                throw FilesClientError.serverMessage(statusCode: 400, message: "Cannot remove the last admin.")
            }
        }
        await store.send(.deleteUserTapped(admin))
        await store.send(.deleteUserConfirmed)
        await store.receive(\.deleteUserResponse) {
            $0.detailErrorMessage = "Cannot remove the last admin."
        }
        #expect(store.state.errorMessage == nil)
    }

    // MARK: Create

    @Test
    func creatingAUserAppendsItToTheList() async {
        let created = makeUser(id: "9")
        let store = await bootedStore(users: [makeUser(id: "1", admin: true)]) {
            $0.filesClient.createUser = { _, _ in created }
        }
        await store.send(.createUserTapped) { $0.createSheet = .init() }
        await store.send(.createEmailChanged("new@example.com"))
        await store.send(.createPasswordChanged("secret1"))
        await store.send(.createSubmitTapped) { $0.createSheet?.isSubmitting = true }
        await store.receive(\.createResponse) {
            $0.createSheet = nil
            $0.users.append(created)
            $0.toast = L10n.UserManagement.toastUserCreated
        }
    }

    @Test
    func createIsBlockedUntilEmailAndASixCharPasswordArePresent() async {
        let store = await bootedStore(users: [])
        await store.send(.createUserTapped)
        await store.send(.createEmailChanged("x@y.z"))
        await store.send(.createPasswordChanged("short"))
        #expect(store.state.createSheet?.isSubmitEnabled == false)
        await store.send(.createPasswordChanged("longer"))
        #expect(store.state.createSheet?.isSubmitEnabled == true)
    }

    @Test
    func createRejectsAMalformedEmailWithAnInlineError() async {
        let store = await bootedStore(users: [])
        await store.send(.createUserTapped)
        await store.send(.createEmailChanged("not-an-email"))
        await store.send(.createPasswordChanged("longenough"))
        #expect(store.state.createSheet?.emailError == L10n.UserManagement.errorEmailInvalid)
        #expect(store.state.createSheet?.isSubmitEnabled == false)
        await store.send(.createEmailChanged("real@example.com"))
        #expect(store.state.createSheet?.emailError == nil)
        #expect(store.state.createSheet?.isSubmitEnabled == true)
    }

    @Test
    func aSetPasswordFailureKeepsTheSheetOpenWithItsMessage() async {
        let store = await bootedStore(users: [makeUser(id: "2")]) {
            $0.filesClient.setUserPassword = { _, _, _ in
                throw FilesClientError.serverMessage(statusCode: 400, message: "Password must be at least 6 characters long.")
            }
        }
        await store.send(.userTapped("2"))
        await store.send(.setPasswordTapped)
        await store.send(.passwordFieldChanged("secret1"))
        await store.send(.passwordSubmitTapped) { $0.passwordSheet?.isSubmitting = true }
        await store.receive(\.passwordResponse) {
            $0.passwordSheet?.isSubmitting = false
            $0.passwordSheet?.errorMessage = "Password must be at least 6 characters long."
        }
        #expect(store.state.passwordSheet != nil)
    }

    @Test
    func aShortPasswordSurfacesAnInlineErrorInTheSetPasswordSheet() async {
        let store = await bootedStore(users: [makeUser(id: "2")])
        await store.send(.userTapped("2"))
        await store.send(.setPasswordTapped)
        await store.send(.passwordFieldChanged("12345"))
        #expect(store.state.passwordSheet?.passwordError == L10n.UserManagement.errorPasswordTooShort(6))
        #expect(store.state.passwordSheet?.isSubmitEnabled == false)
        await store.send(.passwordFieldChanged("123456"))
        #expect(store.state.passwordSheet?.passwordError == nil)
        #expect(store.state.passwordSheet?.isSubmitEnabled == true)
    }

    @Test
    func aProfileSaveIsBlockedByAnEmptyUsername() async {
        let store = await bootedStore(users: [makeUser(id: "2")]) {
            $0.filesClient.updateUser = { _, _, _ in Issue.record("must not reach the server"); throw FilesClientError.network("x") }
        }
        await store.send(.userTapped("2"))
        await store.send(.editUsernameChanged("   "))
        #expect(store.state.profileUsernameError == L10n.UserManagement.errorUsernameRequired)
        #expect(store.state.isProfileSaveEnabled == false)
        await store.send(.saveProfileTapped)  // guarded, no effect
        await store.send(.editUsernameChanged("renamed"))
        #expect(store.state.profileUsernameError == nil)
        #expect(store.state.isProfileSaveEnabled == true)
    }

    @Test
    func aProfileSaveIsBlockedByAnEmptyOrMalformedEmail() async {
        let store = await bootedStore(users: [makeUser(id: "2")]) {
            $0.filesClient.updateUser = { _, _, _ in Issue.record("must not reach the server"); throw FilesClientError.network("x") }
        }
        await store.send(.userTapped("2"))
        await store.send(.editEmailChanged(""))
        #expect(store.state.profileEmailError == L10n.UserManagement.errorEmailRequired)
        #expect(store.state.isProfileSaveEnabled == false)
        await store.send(.saveProfileTapped)  // guarded, no effect

        await store.send(.editEmailChanged("broken@"))
        #expect(store.state.profileEmailError == L10n.UserManagement.errorEmailInvalid)
        await store.send(.editEmailChanged("fixed@example.com"))
        #expect(store.state.profileEmailError == nil)
        #expect(store.state.isProfileSaveEnabled == true)
    }

    // MARK: Password

    @Test
    func settingAPasswordToastsAndReloadsTheList() async {
        let user = makeUser(id: "2", password: false, oidc: true)
        let refreshed = [makeUser(id: "2", password: true, oidc: true)]
        let store = await bootedStore(users: [user]) {
            $0.filesClient.setUserPassword = { _, _, _ in }
        }
        await store.send(.userTapped("2"))
        store.dependencies.filesClient.listUsers = { _ in refreshed }

        await store.send(.setPasswordTapped) {
            $0.passwordSheet = .init(userID: "2", userLabel: "User 2", hasExistingPassword: false)
        }
        await store.send(.passwordFieldChanged("secret1"))
        await store.send(.passwordSubmitTapped) { $0.passwordSheet?.isSubmitting = true }
        await store.receive(\.passwordResponse) {
            $0.passwordSheet = nil
            $0.toast = L10n.UserManagement.toastPasswordUpdated
        }
        await store.receive(\.usersResponse) {
            $0.users = IdentifiedArray(uniqueElements: refreshed)
        }
        #expect(store.state.users[id: "2"]?.hasLocalPassword == true)
    }

    // MARK: Volumes

    @Test
    func assigningAVolumeAddsItToTheDetail() async {
        let created = UserVolume(id: "v9", userId: "2", label: "Media", path: "/srv/media", accessMode: .readonly)
        let store = await bootedStore(users: [makeUser(id: "2")], volumesEnabled: true) {
            $0.filesClient.addUserVolume = { _, _, _ in created }
        }
        await store.send(.userTapped("2"))
        await store.receive(\.volumesResponse)

        await store.send(.addVolumeTapped) { $0.volumeSheet = .init(userID: "2") }
        await store.send(.volumePathSelected("/srv/media")) {
            $0.volumeSheet?.selectedPath = "/srv/media"
            $0.volumeSheet?.label = "media"
        }
        await store.send(.volumeLabelChanged("Media"))
        await store.send(.volumeAccessModeChanged(.readonly))
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse) {
            $0.volumeSheet = nil
            $0.volumes[id: "v9"] = created
            $0.toast = L10n.UserManagement.toastVolumeSaved
        }
    }

    @Test
    func removingAVolumeDropsItFromTheDetail() async {
        let volume = UserVolume(id: "v1", userId: "2", label: "Projects", path: "/srv/projects", accessMode: .readwrite)
        let store = await bootedStore(users: [makeUser(id: "2")], volumesEnabled: true) {
            $0.filesClient.userVolumes = { _, _ in [volume] }
            $0.filesClient.removeUserVolume = { _, _, _ in }
        }
        await store.send(.userTapped("2"))
        await store.receive(\.volumesResponse)

        await store.send(.removeVolumeTapped(volume)) { $0.volumeToRemove = volume }
        await store.send(.removeVolumeConfirmed) { $0.volumeToRemove = nil }
        await store.receive(\.removeVolumeResponse) {
            $0.volumes.remove(id: "v1")
            $0.toast = L10n.UserManagement.toastVolumeRemoved
        }
    }

    @Test
    func editingAVolumeGoesThroughUpdateNotAdd() async {
        let volume = UserVolume(id: "v1", userId: "2", label: "Projects", path: "/srv/projects", accessMode: .readwrite)
        let saved = UserVolume(id: "v1", userId: "2", label: "Renamed", path: "/srv/projects", accessMode: .readonly)
        let store = await bootedStore(users: [makeUser(id: "2")], volumesEnabled: true) {
            $0.filesClient.userVolumes = { _, _ in [volume] }
            $0.filesClient.addUserVolume = { _, _, _ in Issue.record("edit must not call add"); throw FilesClientError.network("x") }
            $0.filesClient.updateUserVolume = { _, _, _, _, _ in saved }
        }
        await store.send(.userTapped("2"))
        await store.receive(\.volumesResponse)

        await store.send(.editVolumeTapped(volume)) {
            $0.volumeSheet = .init(
                userID: "2", editingVolumeID: "v1", label: "Projects",
                selectedPath: "/srv/projects", accessMode: .readwrite
            )
        }
        await store.send(.volumeLabelChanged("Renamed"))
        await store.send(.volumeAccessModeChanged(.readonly))
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse) {
            $0.volumeSheet = nil
            $0.volumes[id: "v1"] = saved
            $0.toast = L10n.UserManagement.toastVolumeSaved
        }
    }

    @Test
    func aVolumeSaveFailureKeepsTheSheetOpenWithItsMessage() async {
        let store = await bootedStore(users: [makeUser(id: "2")], volumesEnabled: true) {
            $0.filesClient.addUserVolume = { _, _, _ in
                throw FilesClientError.serverMessage(statusCode: 409, message: "This path is already assigned to this user")
            }
        }
        await store.send(.userTapped("2"))
        await store.receive(\.volumesResponse)
        await store.send(.addVolumeTapped) { $0.volumeSheet = .init(userID: "2") }
        await store.send(.volumePathSelected("/srv/media"))
        await store.send(.volumeLabelChanged("Media"))
        await store.send(.volumeSubmitTapped) { $0.volumeSheet?.isSubmitting = true }
        await store.receive(\.volumeResponse) {
            $0.volumeSheet?.isSubmitting = false
            $0.volumeSheet?.errorMessage = "This path is already assigned to this user"
        }
    }

    @Test
    func aRemoveVolumeFailureIsSurfaced() async {
        let volume = UserVolume(id: "v1", userId: "2", label: "Projects", path: "/srv/projects", accessMode: .readwrite)
        let store = await bootedStore(users: [makeUser(id: "2")], volumesEnabled: true) {
            $0.filesClient.userVolumes = { _, _ in [volume] }
            $0.filesClient.removeUserVolume = { _, _, _ in throw FilesClientError.server(statusCode: 500) }
        }
        await store.send(.userTapped("2"))
        await store.receive(\.volumesResponse)
        await store.send(.removeVolumeTapped(volume))
        await store.send(.removeVolumeConfirmed)
        await store.receive(\.removeVolumeResponse) {
            $0.detailErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
        #expect(store.state.volumes[id: "v1"] != nil)
    }

    @Test
    func switchingToTheVolumesTabLoadsThemLazily() async {
        let volume = UserVolume(id: "v1", userId: "2", label: "Projects", path: "/srv/projects", accessMode: .readwrite)
        let store = await bootedStore(users: [makeUser(id: "2")], volumesEnabled: true) {
            $0.filesClient.userVolumes = { _, _ in [volume] }
        }
        await store.send(.userTapped("2"))
        await store.receive(\.volumesResponse) { $0.volumes = [volume] }
        // Server list is now empty; switching tabs refetches only when nothing is loaded.
        store.dependencies.filesClient.userVolumes = { _, _ in [] }
        await store.send(.detailTabChanged(.security))
        await store.send(.detailTabChanged(.volumes))  // volumes already loaded → no refetch
        #expect(store.state.volumes.count == 1)
    }

    // MARK: Create failure

    @Test
    func aCreateUserFailureKeepsTheSheetOpenWithItsMessage() async {
        let store = await bootedStore(users: []) {
            $0.filesClient.createUser = { _, _ in
                throw FilesClientError.serverMessage(statusCode: 409, message: "Email already in use.")
            }
        }
        await store.send(.createUserTapped)
        await store.send(.createEmailChanged("dupe@example.com"))
        await store.send(.createPasswordChanged("longenough"))
        await store.send(.createSubmitTapped) { $0.createSheet?.isSubmitting = true }
        await store.receive(\.createResponse) {
            $0.createSheet?.isSubmitting = false
            $0.createSheet?.errorMessage = "Email already in use."
        }
        #expect(store.state.createSheet != nil)
    }

    // MARK: Unexpected states

    @Test
    func aBackgroundReloadThatDropsTheOpenUserClosesTheDetail() async {
        let remaining = [makeUser(id: "1", admin: true)]
        let store = await bootedStore(users: [makeUser(id: "1", admin: true), makeUser(id: "2")])
        await store.send(.userTapped("2"))
        #expect(store.state.detailUserID == "2")

        store.dependencies.filesClient.listUsers = { _ in remaining }
        await store.send(.refreshRequested)
        await store.receive(\.usersResponse) {
            $0.users = IdentifiedArray(uniqueElements: remaining)
            $0.detailUserID = nil
        }
    }

    @Test
    func aBackgroundReloadDoesNotStompUnsavedProfileEdits() async {
        let same = [makeUser(id: "2")]
        let store = await bootedStore(users: same)
        await store.send(.userTapped("2"))
        await store.send(.editDisplayNameChanged("Half-typed name"))

        store.dependencies.filesClient.listUsers = { _ in same }
        await store.send(.refreshRequested)
        await store.receive(\.usersResponse)
        #expect(store.state.editDisplayName == "Half-typed name")
    }

    // MARK: Search

    @Test
    func searchFiltersByNameUsernameOrEmail() async {
        let users = [
            makeUser(id: "1"),
            User(id: "2", username: "jrivera", email: "jamie@corp.com", displayName: "Jamie Rivera"),
            User(id: "3", username: "sokafor", email: "sam@corp.com", displayName: "Sam Okafor")
        ]
        let store = await bootedStore(users: users)

        await store.send(.searchQueryChanged("rivera")) { $0.searchQuery = "rivera" }
        #expect(store.state.displayedUsers.map(\.id) == ["2"])

        await store.send(.searchQueryChanged("corp.com"))
        #expect(store.state.displayedUsers.map(\.id) == ["2", "3"])

        await store.send(.searchQueryChanged("nobody"))
        #expect(store.state.isSearchWithoutResults)
    }

    // MARK: Sort

    @Test
    func theListSortsByTypeThenNameByDefaultAndFollowsTheSortSheet() async {
        let users = [
            User(id: "1", username: "amy", email: "amy@corp.com", displayName: "Amy"),
            User(id: "2", username: "mia", email: "mia@corp.com", displayName: "Mia", roles: ["admin"]),
            User(id: "3", username: "zoe", email: "zoe@corp.com", displayName: "Zoe")
        ]
        let store = await bootedStore(users: users)

        // Default: .type ascending, admin (Mia) first, then non admins by name.
        #expect(store.state.displayedUsers.map(\.id) == ["2", "1", "3"])

        await store.send(.sortOptionChanged(.name))
        #expect(store.state.displayedUsers.map(\.id) == ["1", "2", "3"])

        await store.send(.sortOptionChanged(.email))
        #expect(store.state.displayedUsers.map(\.id) == ["1", "2", "3"])

        await store.send(.sortDirectionChanged(.descending))
        #expect(store.state.displayedUsers.map(\.id) == ["3", "2", "1"])
    }
}
