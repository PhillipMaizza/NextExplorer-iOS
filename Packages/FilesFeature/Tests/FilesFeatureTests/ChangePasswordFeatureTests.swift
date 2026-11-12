import ComposableArchitecture
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing

@MainActor
struct ChangePasswordFeatureTests {
    private typealias Store = TestStoreOf<ChangePasswordFeature>

    struct ChangeCall: Equatable, Sendable {
        let current: String
        let new: String
    }

    private let serverURL = SettingsTestSupport.serverURL
    private let changeCalls = LockIsolated<[ChangeCall]>([])
    private let addCalls = LockIsolated<[String]>([])

    private func makeStore(
        mode: ChangePasswordFeature.Mode = .change,
        change: @escaping @Sendable () async throws -> Void = { throw FilesClientError.offline },
        add: @escaping @Sendable () async throws -> Void = { throw FilesClientError.offline }
    ) -> Store {
        let changeCalls = changeCalls
        let addCalls = addCalls
        return TestStore(initialState: ChangePasswordFeature.State(serverURL: serverURL, mode: mode)) {
            ChangePasswordFeature()
        } withDependencies: {
            $0.filesClient.changeOwnPassword = { _, current, new in
                changeCalls.withValue { $0.append(ChangeCall(current: current, new: new)) }
                try await change()
            }
            $0.filesClient.addOwnPassword = { _, password in
                addCalls.withValue { $0.append(password) }
                try await add()
            }
        }
    }

    private func fillNew(_ store: Store, _ password: String, confirm: String? = nil) async {
        let confirmation = confirm ?? password
        if store.state.newPassword != password {
            await store.send(.newPasswordChanged(password)) { $0.newPassword = password }
        }
        if store.state.confirmPassword != confirmation {
            await store.send(.confirmPasswordChanged(confirmation)) { $0.confirmPassword = confirmation }
        }
    }

    private func fillChange(_ store: Store, current: String = "old-pass", new: String = "the-new-one") async {
        await store.send(.currentPasswordChanged(current)) { $0.currentPassword = current }
        await fillNew(store, new)
    }

    // MARK: Add mode (an account with no password yet)

    @Test
    func addModeNeedsNoCurrentPassword() async {
        let store = makeStore(mode: .add)
        #expect(!store.state.isSubmitEnabled)

        await fillNew(store, "brand-new")

        #expect(store.state.currentPassword.isEmpty)
        #expect(store.state.isSubmitEnabled)
    }

    @Test
    func addModeStillChecksLengthAndMatch() async {
        let store = makeStore(mode: .add)

        await fillNew(store, "short")
        #expect(!store.state.isSubmitEnabled)

        await store.send(.newPasswordChanged("brand-new")) { $0.newPassword = "brand-new" }
        #expect(store.state.confirmError == .mismatch)
        #expect(!store.state.isSubmitEnabled)
    }

    @Test
    func addModeSendsOnlyTheNewPasswordToTheAddRouteAndReportsIt() async {
        let store = makeStore(mode: .add, add: {})
        await fillNew(store, "brand-new")

        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.success) {
            $0.isSubmitting = false
            $0.newPassword = ""
            $0.confirmPassword = ""
            $0.didSucceed = true
        }
        await store.receive(.delegate(.passwordAdded))

        #expect(addCalls.value == ["brand-new"])
        #expect(changeCalls.value.isEmpty)
    }

    @Test
    func addModeSurfacesAnAlreadyHasPasswordError() async {
        let store = makeStore(mode: .add, add: {
            throw FilesClientError.serverMessage(statusCode: 409, message: "You already have password authentication.")
        })
        await fillNew(store, "brand-new")

        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.failure) {
            $0.isSubmitting = false
            $0.errorMessage = "You already have password authentication."
        }
        #expect(!store.state.didSucceed)
        #expect(store.state.newPassword == "brand-new")
    }

    @Test
    func changeModeNeverReportsAnAddedPassword() async {
        let store = makeStore(change: {})
        await fillChange(store)

        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.success) {
            $0.isSubmitting = false
            $0.currentPassword = ""
            $0.newPassword = ""
            $0.confirmPassword = ""
            $0.didSucceed = true
        }
        await store.finish()
        #expect(addCalls.value.isEmpty)
    }

    // MARK: Validation

    struct LengthCase: Sendable {
        let password: String
        let error: ChangePasswordFeature.NewPasswordError?
        let isSubmittable: Bool
    }

    @Test(
        "The new password needs at least six characters, and an empty field is not yet an error",
        arguments: [
            LengthCase(password: "", error: nil, isSubmittable: false),
            LengthCase(password: "a", error: .tooShort(minimum: 6), isSubmittable: false),
            LengthCase(password: "12345", error: .tooShort(minimum: 6), isSubmittable: false),
            LengthCase(password: "123456", error: nil, isSubmittable: true),
            LengthCase(password: "a much longer passphrase", error: nil, isSubmittable: true),
        ]
    )
    func newPasswordLengthBoundary(_ testCase: LengthCase) async {
        let store = makeStore()
        await fillChange(store, new: testCase.password)

        #expect(store.state.newPasswordError == testCase.error)
        #expect(store.state.isSubmitEnabled == testCase.isSubmittable)
    }

    @Test
    func submitIsGatedOnAllThreeFields() async {
        let store = makeStore()
        #expect(!store.state.isSubmitEnabled)

        await fillNew(store, "brand-new")
        #expect(!store.state.isSubmitEnabled)

        await store.send(.currentPasswordChanged("old-pass")) { $0.currentPassword = "old-pass" }
        #expect(store.state.isSubmitEnabled)

        await store.send(.confirmPasswordChanged("brand-neW")) { $0.confirmPassword = "brand-neW" }
        #expect(store.state.confirmError == .mismatch)
        #expect(!store.state.isSubmitEnabled)

        await store.send(.confirmPasswordChanged("brand-new")) { $0.confirmPassword = "brand-new" }
        #expect(store.state.confirmError == nil)
        #expect(store.state.isSubmitEnabled)
    }

    @Test
    func aGuardedSubmitDoesNothing() async {
        let store = makeStore(change: {})

        await store.send(.submitTapped)
        #expect(changeCalls.value.isEmpty)
        #expect(addCalls.value.isEmpty)
    }

    // MARK: Happy path

    @Test
    func aSuccessfulChangeSendsBothPasswordsAndClearsTheForm() async {
        let store = makeStore(change: {})
        await fillChange(store)

        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.success) {
            $0.isSubmitting = false
            $0.currentPassword = ""
            $0.newPassword = ""
            $0.confirmPassword = ""
            $0.didSucceed = true
        }
        #expect(changeCalls.value == [ChangeCall(current: "old-pass", new: "the-new-one")])
    }

    @Test(
        "Typing in any field again clears a stale success message",
        arguments: [
            ChangePasswordFeature.Action.currentPasswordChanged("x"),
            .newPasswordChanged("x"),
            .confirmPasswordChanged("x"),
        ]
    )
    func typingAgainClearsAStaleSuccessMessage(_ action: ChangePasswordFeature.Action) async {
        var state = ChangePasswordFeature.State(serverURL: serverURL)
        state.didSucceed = true
        let store = TestStore(initialState: state) { ChangePasswordFeature() }

        await store.send(action) {
            switch action {
            case .currentPasswordChanged: $0.currentPassword = "x"
            case .newPasswordChanged: $0.newPassword = "x"
            default: $0.confirmPassword = "x"
            }
            $0.didSucceed = false
        }
    }

    // MARK: Error paths

    @Test
    func aWrongCurrentPasswordSurfacesTheServerMessageAndKeepsTheForm() async {
        let store = makeStore(change: {
            throw FilesClientError.serverMessage(statusCode: 401, message: "Current password is incorrect.")
        })
        await fillChange(store, current: "nope")

        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.failure) {
            $0.isSubmitting = false
            $0.errorMessage = "Current password is incorrect."
        }
        #expect(store.state.currentPassword == "nope")
        #expect(store.state.newPassword == "the-new-one")
    }

    @Test
    func aRateLimitIsSurfaced() async {
        let store = makeStore(change: { throw FilesClientError.rateLimited })
        await fillChange(store)

        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.failure) {
            $0.isSubmitting = false
            $0.errorMessage = L10n.Error.rateLimited
        }
    }

    @Test
    func resubmittingAfterAFailureClearsTheOldError() async {
        let attempts = LockIsolated(0)
        let store = makeStore(change: {
            if attempts.withValue({ $0 += 1; return $0 }) == 1 { throw FilesClientError.rateLimited }
        })
        await fillChange(store)

        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.response.failure) {
            $0.isSubmitting = false
            $0.errorMessage = L10n.Error.rateLimited
        }
        await store.send(.submitTapped) {
            $0.isSubmitting = true
            $0.errorMessage = nil
        }
        await store.receive(\.response.success) {
            $0.isSubmitting = false
            $0.currentPassword = ""
            $0.newPassword = ""
            $0.confirmPassword = ""
            $0.didSucceed = true
        }
        #expect(attempts.value == 2)
    }
}
