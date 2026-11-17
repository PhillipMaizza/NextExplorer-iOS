import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct UserManagementAccountTests: UserManagementTestSupport {
    let calls = LockIsolated<[Call]>([])
    let listCalls = LockIsolated(0)
    let featureCalls = LockIsolated(0)
    let volumeLoads = LockIsolated<[String]>([])

    @Test
    func savingTheProfileSendsTheTrimmedFieldsThenUpdatesTheUserAndToasts() async {
        let user = makeUser(id: "2")
        let updated = User(
            id: "2",
            username: "user2",
            email: "new@example.com",
            displayName: "Renamed",
            roles: [],
            authMethods: user.authMethods
        )
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
        #expect(calls.value == [.updateUser(
            id: "2",
            request: UpdateUserRequest(email: "new@example.com", username: "user2", displayName: "Renamed")
        )])
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
            ProfileEditCase(
                username: "renamed",
                email: "user2@example.com",
                usernameError: nil,
                emailError: nil,
                isSaveEnabled: true
            ),
            ProfileEditCase(
                username: TestValue.blank, email: "user2@example.com",
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
            ProfileEditCase(
                username: "user2",
                email: "user2@example.com",
                usernameError: nil,
                emailError: nil,
                isSaveEnabled: false
            ),
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

    @Test
    func grantingAdminAsksFirstThenSendsTheRolesAndToasts() async {
        let user = makeUser(id: "2")
        let promoted = User(
            id: "2",
            username: "user2",
            email: "user2@example.com",
            displayName: "User 2",
            roles: ["admin"],
            authMethods: user.authMethods
        )
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
        let promoted = User(
            id: "2",
            username: "user2",
            email: "user2@example.com",
            roles: ["admin", "editor", "viewer"]
        )
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
}
