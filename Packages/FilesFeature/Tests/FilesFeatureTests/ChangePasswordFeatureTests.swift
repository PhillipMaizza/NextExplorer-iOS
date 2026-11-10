import ComposableArchitecture
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct ChangePasswordFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    private func store(
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ChangePasswordFeature> {
        let store = TestStore(initialState: ChangePasswordFeature.State(serverURL: serverURL)) {
            ChangePasswordFeature()
        } withDependencies: { configure(&$0) }
        store.exhaustivity = .off
        return store
    }

    private func addStore(
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ChangePasswordFeature> {
        let store = TestStore(initialState: ChangePasswordFeature.State(serverURL: serverURL, mode: .add)) {
            ChangePasswordFeature()
        } withDependencies: { configure(&$0) }
        store.exhaustivity = .off
        return store
    }

    // MARK: Add mode (an account with no password yet)

    @Test
    func addModeNeedsNoCurrentPassword() async {
        let store = addStore()
        #expect(store.state.isSubmitEnabled == false)

        await store.send(.newPasswordChanged("brand-new"))
        await store.send(.confirmPasswordChanged("brand-new"))

        #expect(store.state.currentPassword.isEmpty)
        #expect(store.state.isSubmitEnabled == true)
    }

    @Test
    func addModeStillChecksLengthAndMatch() async {
        let store = addStore()

        await store.send(.newPasswordChanged("short"))
        await store.send(.confirmPasswordChanged("short"))
        #expect(store.state.isSubmitEnabled == false)

        await store.send(.newPasswordChanged("brand-new"))
        #expect(store.state.confirmError == .mismatch)
        #expect(store.state.isSubmitEnabled == false)
    }

    @Test
    func addModeSendsOnlyTheNewPasswordToTheAddRouteAndReportsIt() async {
        let sent = LockIsolated<String?>(nil)
        let store = addStore {
            $0.filesClient.addOwnPassword = { _, password in sent.setValue(password) }
            $0.filesClient.changeOwnPassword = { _, _, _ in Issue.record("add mode must not call the change route") }
        }
        await store.send(.newPasswordChanged("brand-new"))
        await store.send(.confirmPasswordChanged("brand-new"))

        await store.send(.submitTapped)
        await store.receive(\.response)
        await store.receive(\.delegate)

        #expect(sent.value == "brand-new")
        #expect(store.state.newPassword.isEmpty)
        #expect(store.state.isSubmitting == false)
    }

    @Test
    func addModeSurfacesAnAlreadyHasPasswordError() async {
        let store = addStore {
            $0.filesClient.addOwnPassword = { _, _ in
                throw FilesClientError.serverMessage(statusCode: 409, message: "You already have password authentication.")
            }
        }
        await store.send(.newPasswordChanged("brand-new"))
        await store.send(.confirmPasswordChanged("brand-new"))

        await store.send(.submitTapped)
        await store.receive(\.response)

        #expect(store.state.errorMessage == "You already have password authentication.")
        #expect(store.state.didSucceed == false)
    }

    @Test
    func changeModeNeverReportsAnAddedPassword() async {
        let store = store {
            $0.filesClient.changeOwnPassword = { _, _, _ in }
        }
        await store.send(.currentPasswordChanged("old-pass"))
        await store.send(.newPasswordChanged("brand-new"))
        await store.send(.confirmPasswordChanged("brand-new"))

        await store.send(.submitTapped)
        await store.receive(\.response)

        #expect(store.state.didSucceed == true)
    }

    // MARK: Validation

    @Test
    func submitIsGatedOnAllThreeFields() async {
        let store = store()
        #expect(store.state.isSubmitEnabled == false)

        await store.send(.currentPasswordChanged("old-pass"))
        await store.send(.newPasswordChanged("short"))
        #expect(store.state.newPasswordError == .tooShort(minimum: 6))
        #expect(store.state.isSubmitEnabled == false)

        await store.send(.newPasswordChanged("brand-new"))
        await store.send(.confirmPasswordChanged("brand-neW"))
        #expect(store.state.confirmError == .mismatch)
        #expect(store.state.isSubmitEnabled == false)

        await store.send(.confirmPasswordChanged("brand-new"))
        #expect(store.state.confirmError == nil)
        #expect(store.state.isSubmitEnabled == true)
    }

    @Test
    func aGuardedSubmitDoesNothing() async {
        let store = store {
            $0.filesClient.changeOwnPassword = { _, _, _ in Issue.record("must not call the server") }
        }
        await store.send(.submitTapped) // nothing filled in
        #expect(store.state.isSubmitting == false)
    }

    // MARK: Happy path

    @Test
    func aSuccessfulChangeClearsTheFormAndShowsSuccess() async {
        let store = store {
            $0.filesClient.changeOwnPassword = { _, current, new in
                #expect(current == "old-pass")
                #expect(new == "the-new-one")
            }
        }
        await store.send(.currentPasswordChanged("old-pass"))
        await store.send(.newPasswordChanged("the-new-one"))
        await store.send(.confirmPasswordChanged("the-new-one"))
        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.success) {
            $0.isSubmitting = false
            $0.currentPassword = ""
            $0.newPassword = ""
            $0.confirmPassword = ""
            $0.didSucceed = true
        }
    }

    @Test
    func typingAgainClearsAStaleSuccessMessage() async {
        let store = store {
            $0.filesClient.changeOwnPassword = { _, _, _ in }
        }
        await store.send(.currentPasswordChanged("old-pass"))
        await store.send(.newPasswordChanged("the-new-one"))
        await store.send(.confirmPasswordChanged("the-new-one"))
        await store.send(.submitTapped)
        await store.receive(\.response.success)
        #expect(store.state.didSucceed)

        await store.send(.currentPasswordChanged("x")) { $0.didSucceed = false }
    }

    // MARK: Error paths

    @Test
    func aWrongCurrentPasswordSurfacesTheServerMessage() async {
        let store = store {
            $0.filesClient.changeOwnPassword = { _, _, _ in
                throw FilesClientError.serverMessage(statusCode: 401, message: "Current password is incorrect.")
            }
        }
        await store.send(.currentPasswordChanged("nope"))
        await store.send(.newPasswordChanged("the-new-one"))
        await store.send(.confirmPasswordChanged("the-new-one"))
        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.failure) {
            $0.isSubmitting = false
            $0.errorMessage = "Current password is incorrect."
        }
        #expect(store.state.currentPassword == "nope") // form is kept for a retry
    }

    @Test
    func aRateLimitIsSurfaced() async {
        let store = store {
            $0.filesClient.changeOwnPassword = { _, _, _ in throw FilesClientError.rateLimited }
        }
        await store.send(.currentPasswordChanged("old-pass"))
        await store.send(.newPasswordChanged("the-new-one"))
        await store.send(.confirmPasswordChanged("the-new-one"))
        await store.send(.submitTapped)
        await store.receive(\.response.failure) {
            $0.isSubmitting = false
            $0.errorMessage = FilesClientError.rateLimited.userMessage
        }
    }
}
