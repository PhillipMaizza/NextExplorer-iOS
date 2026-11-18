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
struct UserManagementCreationTests: UserManagementTestSupport {
    let calls = LockIsolated<[Call]>([])
    let listCalls = LockIsolated(0)
    let featureCalls = LockIsolated(0)
    let volumeLoads = LockIsolated<[String]>([])

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
        #expect(calls.value == [.createUser(CreateUserRequest(
            email: "new@example.com",
            username: "newbie",
            password: "secret1",
            isAdmin: true
        ))])
    }

    @Test(
        "A blank username is sent as no username",
        arguments: ["", TestValue.blank]
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
        #expect(calls.value == [.createUser(CreateUserRequest(
            email: "new@example.com",
            username: nil,
            password: "secret1",
            isAdmin: false
        ))])
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
            CreateCase(
                email: "x@y.z",
                password: TestAccount.totpCode,
                emailError: nil,
                passwordError: nil,
                isSubmitEnabled: true
            ),
            CreateCase(
                email: "x@y.z",
                password: "12345",
                emailError: nil,
                passwordError: L10n.UserManagement.errorPasswordTooShort(6),
                isSubmitEnabled: false
            ),
            CreateCase(
                email: "not-an-email",
                password: "longenough",
                emailError: L10n.UserManagement.errorEmailInvalid,
                passwordError: nil,
                isSubmitEnabled: false
            ),
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
        let sheet = UserManagementFeature.CreateUserState(
            email: "x@y.z",
            password: TestAccount.totpCode,
            isSubmitting: true
        )

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
            throw FilesClientError.serverMessage(
                statusCode: 400,
                message: "Password must be at least 6 characters long."
            )
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
            (TestAccount.totpCode, nil, true),
        ] as [(String, String?, Bool)]
    )
    func passwordSheetValidation(password: String, error: String?, isSubmitEnabled: Bool) {
        let sheet = UserManagementFeature.PasswordSheetState(
            userID: "2",
            userLabel: "User 2",
            hasExistingPassword: true,
            password: password
        )

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
}
