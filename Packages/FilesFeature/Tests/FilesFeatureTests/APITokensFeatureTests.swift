import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import TestUtils
import Testing

@Suite(.isolatedDependencies)
@MainActor
struct APITokensFeatureTests {
    private typealias Store = TestStoreOf<APITokensFeature>

    struct CreateCall: Equatable, Sendable {
        let name: String
        let scope: APIToken.Scope
        let days: Int?
        let password: String?
    }

    struct RenameCall: Equatable, Sendable {
        let id: String
        let name: String
    }

    private let serverURL = SettingsTestSupport.serverURL
    private let backup = APIToken(id: "t1", name: "backup", scope: .read, createdAt: "2026-11-10T07:00:00.000Z")
    private let nightly = APIToken(id: "t2", name: "nightly", scope: .write, createdAt: "2026-11-11T07:00:00.000Z", expiresAt: "2027-01-01T00:00:00.000Z")
    private let wrongPassword = FilesClientError.serverMessage(statusCode: 401, message: "That password is not right.")
    private let createCalls = LockIsolated<[CreateCall]>([])
    private let renameCalls = LockIsolated<[RenameCall]>([])
    private let revokeCalls = LockIsolated<[String]>([])

    private func makeStore(
        requiresPassword: Bool = true,
        phase: APITokensFeature.Phase = .loaded,
        tokens: [APIToken]? = nil,
        list: @escaping @Sendable () async throws -> [APIToken] = { throw FilesClientError.offline },
        create: @escaping @Sendable () async throws -> IssuedAPIToken = { throw FilesClientError.offline },
        rename: @escaping @Sendable () async throws -> APIToken = { throw FilesClientError.offline },
        revoke: @escaping @Sendable () async throws -> Void = { throw FilesClientError.offline },
        initial: (inout APITokensFeature.State) -> Void = { _ in }
    ) -> Store {
        var state = APITokensFeature.State(serverURL: serverURL, requiresPassword: requiresPassword, phase: phase, tokens: tokens ?? [backup])
        initial(&state)
        let createCalls = createCalls
        let renameCalls = renameCalls
        let revokeCalls = revokeCalls
        return TestStore(initialState: state) {
            APITokensFeature()
        } withDependencies: {
            $0.filesClient.fetchAPITokens = { _ in try await list() }
            $0.filesClient.createAPIToken = { _, name, scope, days, password in
                createCalls.withValue { $0.append(CreateCall(name: name, scope: scope, days: days, password: password)) }
                return try await create()
            }
            $0.filesClient.renameAPIToken = { _, id, name in
                renameCalls.withValue { $0.append(RenameCall(id: id, name: name)) }
                return try await rename()
            }
            $0.filesClient.revokeAPIToken = { _, id in
                revokeCalls.withValue { $0.append(id) }
                try await revoke()
            }
        }
    }

    private func tokens(count: Int) -> [APIToken] {
        (0 ..< count).map { APIToken(id: "t\($0)", name: "n\($0)", scope: .read, createdAt: "2026-11-10T07:00:00.000Z") }
    }

    private func openedForm(_ store: Store, name: String = "ci", password: String? = nil) async {
        await store.send(.newTokenTapped) { $0.createForm = APITokensFeature.CreateForm() }
        await store.send(.nameChanged(name)) { $0.createForm?.name = name }
        if let password {
            await store.send(.passwordChanged(password)) { $0.createForm?.password = password }
        }
    }

    // MARK: Loading

    @Test
    func loadingFillsTheList() async {
        let store = makeStore(phase: .loading, tokens: [], list: { [backup, nightly] })

        await store.send(.task)
        await store.receive(\.listResponse.success) {
            $0.tokens = [backup, nightly]
            $0.phase = .loaded
        }
    }

    @Test
    func anAccountWithNoTokensLoadsAnEmptyList() async {
        let store = makeStore(phase: .loading, tokens: [], list: { [] })

        await store.send(.task)
        await store.receive(\.listResponse.success) { $0.phase = .loaded }
    }

    @Test
    func aFailedLoadShowsTheMessageAndRetryLoadsAgain() async {
        let attempts = LockIsolated(0)
        let store = makeStore(phase: .loading, tokens: [], list: {
            if attempts.withValue({ $0 += 1; return $0 }) == 1 {
                throw FilesClientError.forbidden(message: "This installation runs without accounts, so it issues no tokens.")
            }
            return [backup]
        })

        await store.send(.task)
        await store.receive(\.listResponse.failure) {
            $0.phase = .failed("This installation runs without accounts, so it issues no tokens.")
        }
        await store.send(.retryTapped) { $0.phase = .loading }
        await store.receive(\.listResponse.success) {
            $0.tokens = [backup]
            $0.phase = .loaded
        }
        #expect(attempts.value == 2)
    }

    // MARK: Create form

    @Test
    func theFormOpensWithReadAccessAndAnExpiry() async {
        let store = makeStore()

        await store.send(.newTokenTapped) {
            $0.createForm = APITokensFeature.CreateForm(name: "", scope: .read, expiry: .days90, password: "")
        }
    }

    @Test
    func openingTheFormClearsAShownError() async {
        let store = makeStore(initial: { $0.errorMessage = "old" })

        await store.send(.newTokenTapped) {
            $0.createForm = APITokensFeature.CreateForm()
            $0.errorMessage = nil
        }
    }

    struct BlockedCase: Sendable {
        let phase: APITokensFeature.Phase
        let count: Int
        let isWorking: Bool
    }

    @Test(arguments: [
        BlockedCase(phase: .loaded, count: 50, isWorking: false),
        BlockedCase(phase: .loading, count: 1, isWorking: false),
        BlockedCase(phase: .failed("x"), count: 1, isWorking: false),
        BlockedCase(phase: .loaded, count: 1, isWorking: true),
    ])
    func theFormDoesNotOpenAtTheLimitBeforeTheListLoadedOrWhileWorking(_ testCase: BlockedCase) async {
        let store = makeStore(phase: testCase.phase, tokens: tokens(count: testCase.count), initial: { $0.isWorking = testCase.isWorking })

        await store.send(.newTokenTapped)
    }

    @Test(arguments: [(0, false), (49, false), (50, true), (51, true)])
    func theLimitIsFiftyTokens(count: Int, isReached: Bool) {
        #expect(makeStore(tokens: tokens(count: count)).state.hasReachedLimit == isReached)
    }

    @Test
    func createNeedsANameAndThePassword() async {
        let store = makeStore()

        await store.send(.newTokenTapped) { $0.createForm = APITokensFeature.CreateForm() }
        #expect(!store.state.isCreateEnabled)

        await store.send(.nameChanged("ci")) { $0.createForm?.name = "ci" }
        #expect(!store.state.isCreateEnabled)

        await store.send(.passwordChanged("hunter2")) { $0.createForm?.password = "hunter2" }
        #expect(store.state.isCreateEnabled)
    }

    @Test
    func anAccountWithoutAPasswordIsNotAskedForOne() async {
        let store = makeStore(requiresPassword: false)

        await openedForm(store)

        #expect(store.state.isCreateEnabled)
    }

    struct NameCase: Sendable {
        let name: String
        let isValid: Bool
    }

    @Test(arguments: [
        NameCase(name: "", isValid: false),
        NameCase(name: "   \n", isValid: false),
        NameCase(name: "  ci  ", isValid: true),
        NameCase(name: String(repeating: "a", count: 60), isValid: true),
        NameCase(name: String(repeating: "a", count: 61), isValid: false),
    ])
    func aBlankOrTooLongNameIsRefused(_ testCase: NameCase) {
        #expect(APITokensFeature.isValid(name: testCase.name) == testCase.isValid)
    }

    @Test
    func theChoicesMapToTheDaysTheServerTakes() {
        #expect(APITokensFeature.Expiry.allCases.map(\.days) == [30, 90, 365, nil])
    }

    @Test
    func createSendsTheTrimmedNameScopeExpiryAndPasswordThenShowsTheSecret() async {
        let issued = IssuedAPIToken(token: nightly, secret: "nxt_abc.def")
        let store = makeStore(create: { issued })

        await store.send(.newTokenTapped) { $0.createForm = APITokensFeature.CreateForm() }
        await store.send(.nameChanged("  nightly  ")) { $0.createForm?.name = "  nightly  " }
        await store.send(.scopeChanged(.write)) { $0.createForm?.scope = .write }
        await store.send(.expiryChanged(.never)) { $0.createForm?.expiry = .never }
        await store.send(.passwordChanged("hunter2")) { $0.createForm?.password = "hunter2" }
        await store.send(.createSubmitted) { $0.isWorking = true }
        await store.receive(\.createResponse.success) {
            $0.isWorking = false
            $0.createForm = nil
            $0.tokens = [backup, nightly]
            $0.issued = issued
        }

        #expect(createCalls.value == [CreateCall(name: "nightly", scope: .write, days: nil, password: "hunter2")])
    }

    @Test
    func anAccountWithoutAPasswordSendsNone() async {
        let issued = IssuedAPIToken(token: nightly, secret: "s")
        let store = makeStore(requiresPassword: false, create: { issued })

        await openedForm(store, password: "left over")
        await store.send(.createSubmitted) { $0.isWorking = true }
        await store.receive(\.createResponse.success) {
            $0.isWorking = false
            $0.createForm = nil
            $0.tokens = [backup, nightly]
            $0.issued = issued
        }

        #expect(createCalls.value == [CreateCall(name: "ci", scope: .read, days: 90, password: nil)])
    }

    @Test
    func aWrongPasswordKeepsTheFormClearsThePasswordAndShowsTheMessage() async {
        let store = makeStore(create: { throw wrongPassword })

        await openedForm(store, password: "nope")
        await store.send(.createSubmitted) { $0.isWorking = true }
        await store.receive(\.createResponse.failure) {
            $0.isWorking = false
            $0.errorMessage = "That password is not right."
            $0.createForm?.password = ""
        }

        #expect(store.state.createForm?.name == "ci")
        #expect(store.state.tokens == [backup])
    }

    struct KeepsPasswordCase: Sendable {
        let error: FilesClientError
        let message: String
    }

    @Test(arguments: [
        KeepsPasswordCase(error: .rateLimited, message: L10n.Error.rateLimited),
        KeepsPasswordCase(error: .serverMessage(statusCode: 500, message: "The server is busy."), message: "The server is busy."),
        KeepsPasswordCase(error: .offline, message: L10n.Error.offline),
    ])
    func anyOtherFailureKeepsThePassword(_ testCase: KeepsPasswordCase) async {
        let store = makeStore(create: { throw testCase.error })

        await openedForm(store, password: "hunter2")
        await store.send(.createSubmitted) { $0.isWorking = true }
        await store.receive(\.createResponse.failure) {
            $0.isWorking = false
            $0.errorMessage = testCase.message
        }

        #expect(store.state.createForm?.password == "hunter2")
    }

    @Test
    func submittingWhileAnotherActionRunsSendsNothing() async {
        let store = makeStore(initial: {
            $0.createForm = APITokensFeature.CreateForm(name: "ci", password: "x")
            $0.isWorking = true
        })

        await store.send(.createSubmitted)

        #expect(createCalls.value.isEmpty)
    }

    @Test
    func submittingAnInvalidFormSendsNothing() async {
        let store = makeStore()

        await openedForm(store, name: "   ", password: "hunter2")
        await store.send(.createSubmitted)

        #expect(createCalls.value.isEmpty)
    }

    @Test
    func cancellingTheFormDropsItAndTheError() async {
        let store = makeStore(initial: {
            $0.createForm = APITokensFeature.CreateForm(name: "ci", password: "x")
            $0.errorMessage = "x"
        })

        await store.send(.createCancelled) {
            $0.createForm = nil
            $0.errorMessage = nil
        }
    }

    @Test
    func cancellingWhileTheCreateIsInFlightStopsWaitingForIt() async {
        let store = makeStore(create: {
            try await suspendUntilCancelled()
            throw FilesClientError.offline
        })

        await openedForm(store, password: "hunter2")
        await store.send(.createSubmitted) { $0.isWorking = true }
        await store.send(.createCancelled) {
            $0.createForm = nil
            $0.isWorking = false
        }
        await store.finish()

        #expect(store.state.tokens == [backup])
    }

    @Test
    func dismissingTheSecretForgetsIt() async {
        let store = makeStore(initial: { $0.issued = IssuedAPIToken(token: nightly, secret: "s") })

        await store.send(.issuedDismissed) { $0.issued = nil }
    }

    // MARK: Rename

    @Test
    func renameStartsFromTheCurrentNameAndReplacesTheTokenInPlace() async {
        let renamed = APIToken(id: "t1", name: "weekly", scope: .read, createdAt: backup.createdAt)
        let store = makeStore(tokens: [backup, nightly], rename: { renamed })

        await store.send(.renameTapped(backup)) { $0.rename = .init(id: "t1", name: "backup") }
        await store.send(.renameNameChanged("  weekly ")) { $0.rename?.name = "  weekly " }
        await store.send(.renameSubmitted) { $0.isWorking = true }
        await store.receive(\.renameResponse.success) {
            $0.isWorking = false
            $0.rename = nil
            $0.tokens = [renamed, nightly]
        }

        #expect(renameCalls.value == [RenameCall(id: "t1", name: "weekly")])
    }

    @Test
    func aRenamedTokenTheListDoesNotHoldLeavesTheListAlone() async {
        let stranger = APIToken(id: "t9", name: "stranger", scope: .read, createdAt: backup.createdAt)
        let store = makeStore(initial: { $0.isWorking = true })

        await store.send(.renameResponse(.success(stranger))) { $0.isWorking = false }
    }

    @Test
    func renameIsRefusedForABlankName() async {
        let store = makeStore()

        await store.send(.renameTapped(backup)) { $0.rename = .init(id: "t1", name: "backup") }
        await store.send(.renameNameChanged("  ")) { $0.rename?.name = "  " }
        await store.send(.renameSubmitted)

        #expect(renameCalls.value.isEmpty)
    }

    @Test
    func aFailedRenameShowsTheMessageAndKeepsTheOldName() async {
        let store = makeStore(rename: { throw FilesClientError.serverMessage(statusCode: 404, message: "There is no such token on this account.") })

        await store.send(.renameTapped(backup)) { $0.rename = .init(id: "t1", name: "backup") }
        await store.send(.renameNameChanged("x")) { $0.rename?.name = "x" }
        await store.send(.renameSubmitted) { $0.isWorking = true }
        await store.receive(\.renameResponse.failure) {
            $0.isWorking = false
            $0.rename = nil
            $0.errorMessage = "There is no such token on this account."
        }

        #expect(store.state.tokens == [backup])
    }

    @Test
    func cancellingARenameClearsItAndTheError() async {
        let store = makeStore(initial: {
            $0.rename = .init(id: "t1", name: "x")
            $0.errorMessage = "old"
        })

        await store.send(.renameCancelled) {
            $0.rename = nil
            $0.errorMessage = nil
        }
    }

    @Test
    func renameAndRevokeDoNotStartWhileAnotherActionRuns() async {
        let store = makeStore(initial: { $0.isWorking = true })

        await store.send(.renameTapped(backup))
        await store.send(.revokeTapped(backup))
    }

    // MARK: Revoke

    @Test
    func revokeAsksFirstAndCancellingChangesNothing() async {
        let store = makeStore()

        await store.send(.revokeTapped(backup)) { $0.tokenPendingRevoke = backup }
        await store.send(.revokeCancelled) { $0.tokenPendingRevoke = nil }

        #expect(store.state.tokens == [backup])
        #expect(revokeCalls.value.isEmpty)
    }

    @Test
    func confirmingRevokeSendsTheIdAndRemovesOnlyThatToken() async {
        let store = makeStore(tokens: [backup, nightly], revoke: {})

        await store.send(.revokeTapped(backup)) { $0.tokenPendingRevoke = backup }
        await store.send(.revokeConfirmed) {
            $0.tokenPendingRevoke = nil
            $0.isWorking = true
        }
        await store.receive(\.revokeResponse.success) {
            $0.isWorking = false
            $0.tokens = [nightly]
        }

        #expect(revokeCalls.value == ["t1"])
    }

    @Test
    func aFailedRevokeKeepsTheTokenAndShowsTheMessage() async {
        let store = makeStore(revoke: { throw FilesClientError.rateLimited })

        await store.send(.revokeTapped(backup)) { $0.tokenPendingRevoke = backup }
        await store.send(.revokeConfirmed) {
            $0.tokenPendingRevoke = nil
            $0.isWorking = true
        }
        await store.receive(\.revokeResponse.failure) {
            $0.isWorking = false
            $0.errorMessage = L10n.Error.rateLimited
        }

        #expect(store.state.tokens == [backup])
    }

    @Test
    func revokeConfirmedWithNothingPendingDoesNothing() async {
        let store = makeStore()

        await store.send(.revokeConfirmed)

        #expect(revokeCalls.value.isEmpty)
    }
}
