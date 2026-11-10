import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct APITokensFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!
    private let backup = APIToken(id: "t1", name: "backup", scope: .read, createdAt: "2026-11-10T07:00:00.000Z")
    private let nightly = APIToken(id: "t2", name: "nightly", scope: .write, createdAt: "2026-11-11T07:00:00.000Z", expiresAt: "2027-01-01T00:00:00.000Z")
    private let wrongPassword = FilesClientError.serverMessage(statusCode: 401, message: "That password is not right.")

    private func makeStore(
        requiresPassword: Bool = true,
        phase: APITokensFeature.Phase = .loaded,
        tokens: [APIToken]? = nil,
        configure: (inout DependencyValues) -> Void = { _ in },
        initial: (inout APITokensFeature.State) -> Void = { _ in }
    ) -> TestStoreOf<APITokensFeature> {
        var state = APITokensFeature.State(serverURL: serverURL, requiresPassword: requiresPassword, phase: phase, tokens: tokens ?? [backup])
        initial(&state)
        let store = TestStore(initialState: state) {
            APITokensFeature()
        } withDependencies: { configure(&$0) }
        store.timeout = .seconds(10)
        return store
    }

    // MARK: Loading

    @Test
    func loadingFillsTheList() async {
        let store = makeStore(phase: .loading, tokens: [], configure: { $0.filesClient.fetchAPITokens = { _ in [backup, nightly] } })

        await store.send(.task)
        await store.receive(\.listResponse) {
            $0.tokens = [backup, nightly]
            $0.phase = .loaded
        }
    }

    @Test
    func anAccountWithNoTokensLoadsAnEmptyList() async {
        let store = makeStore(phase: .loading, tokens: [], configure: { $0.filesClient.fetchAPITokens = { _ in [] } })

        await store.send(.task)
        await store.receive(\.listResponse) { $0.phase = .loaded }
    }

    @Test
    func aFailedLoadShowsTheMessageAndRetryLoadsAgain() async {
        let refusal = FilesClientError.forbidden(message: "This installation runs without accounts, so it issues no tokens.")
        let attempts = LockIsolated(0)
        let store = makeStore(phase: .loading, tokens: [], configure: {
            $0.filesClient.fetchAPITokens = { _ in
                if attempts.withValue({ $0 += 1; return $0 }) == 1 {
                    throw refusal
                }
                return [backup]
            }
        })

        await store.send(.task)
        await store.receive(\.listResponse) { $0.phase = .failed(refusal.userMessage) }
        await store.send(.retryTapped) { $0.phase = .loading }
        await store.receive(\.listResponse) {
            $0.tokens = [backup]
            $0.phase = .loaded
        }
    }

    // MARK: Create form

    @Test
    func theFormOpensWithReadAccessAndAnExpiry() async {
        let store = makeStore()

        await store.send(.newTokenTapped) { $0.createForm = APITokensFeature.CreateForm() }
        #expect(store.state.createForm?.scope == .read)
        #expect(store.state.createForm?.expiry == .days90)
    }

    @Test
    func theFormDoesNotOpenAtTheLimitOrBeforeTheListLoaded() async {
        let full = (0 ..< APITokenLimits.maxTokensPerAccount).map { APIToken(id: "t\($0)", name: "n\($0)", scope: .read, createdAt: "2026-11-10T07:00:00.000Z") }
        #expect(makeStore(tokens: full).state.hasReachedLimit)
        await makeStore(tokens: full).send(.newTokenTapped)
        await makeStore(phase: .loading).send(.newTokenTapped)
        await makeStore(phase: .failed("x")).send(.newTokenTapped)
    }

    @Test
    func theLimitIsFiftyAndFortyNineStillAllowsOne() {
        let almost = (0 ..< 49).map { APIToken(id: "t\($0)", name: "n\($0)", scope: .read, createdAt: "2026-11-10T07:00:00.000Z") }
        #expect(!makeStore(tokens: almost).state.hasReachedLimit)
    }

    @Test
    func createNeedsANameAndThePassword() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.newTokenTapped)
        #expect(!store.state.isCreateEnabled)

        await store.send(.nameChanged("ci"))
        #expect(!store.state.isCreateEnabled)
        await store.send(.passwordChanged("hunter2"))
        #expect(store.state.isCreateEnabled)
    }

    @Test
    func anAccountWithoutAPasswordIsNotAskedForOne() async {
        let store = makeStore(requiresPassword: false)
        store.exhaustivity = .off
        await store.send(.newTokenTapped)
        await store.send(.nameChanged("ci"))

        #expect(store.state.isCreateEnabled)
    }

    @Test
    func aBlankOrTooLongNameIsRefused() {
        #expect(!APITokensFeature.isValid(name: ""))
        #expect(!APITokensFeature.isValid(name: "   \n"))
        #expect(APITokensFeature.isValid(name: "  ci  "))
        #expect(APITokensFeature.isValid(name: String(repeating: "a", count: APITokenLimits.maxNameLength)))
        #expect(!APITokensFeature.isValid(name: String(repeating: "a", count: APITokenLimits.maxNameLength + 1)))
    }

    @Test
    func theChoicesMapToTheDaysTheServerTakes() {
        #expect(APITokensFeature.Expiry.allCases.map(\.days) == [30, 90, 365, nil])
    }

    @Test
    func createSendsTheTrimmedNameScopeExpiryAndPasswordThenShowsTheSecret() async {
        let sent = LockIsolated<[String]>([])
        let issued = IssuedAPIToken(token: nightly, secret: "nxt_abc.def")
        let store = makeStore(configure: {
            $0.filesClient.createAPIToken = { _, name, scope, days, password in
                sent.setValue([name, scope.rawValue, String(describing: days), password ?? "nil"])
                return issued
            }
        })
        store.exhaustivity = .off

        await store.send(.newTokenTapped)
        await store.send(.nameChanged("  nightly  "))
        await store.send(.scopeChanged(.write))
        await store.send(.expiryChanged(.never))
        await store.send(.passwordChanged("hunter2"))
        await store.send(.createSubmitted)
        await store.receive(\.createResponse)

        #expect(sent.value == ["nightly", "write", "nil", "hunter2"])
        #expect(store.state.createForm == nil)
        #expect(store.state.issued == issued)
        #expect(store.state.tokens == [backup, nightly])
        #expect(!store.state.isWorking)
    }

    @Test
    func anAccountWithoutAPasswordSendsNone() async {
        let sentPassword = LockIsolated<String?>("unset")
        let store = makeStore(requiresPassword: false, configure: {
            $0.filesClient.createAPIToken = { _, _, _, _, password in
                sentPassword.setValue(password)
                return IssuedAPIToken(token: nightly, secret: "s")
            }
        })
        store.exhaustivity = .off

        await store.send(.newTokenTapped)
        await store.send(.nameChanged("ci"))
        await store.send(.passwordChanged("left over"))
        await store.send(.createSubmitted)
        await store.receive(\.createResponse)

        #expect(sentPassword.value == nil)
    }

    @Test
    func aWrongPasswordKeepsTheFormClearsThePasswordAndShowsTheMessage() async {
        let store = makeStore(configure: { $0.filesClient.createAPIToken = { _, _, _, _, _ in throw wrongPassword } })
        store.exhaustivity = .off

        await store.send(.newTokenTapped)
        await store.send(.nameChanged("ci"))
        await store.send(.passwordChanged("nope"))
        await store.send(.createSubmitted)
        await store.receive(\.createResponse)

        #expect(store.state.createForm?.name == "ci")
        #expect(store.state.createForm?.password == "")
        #expect(store.state.errorMessage == wrongPassword.userMessage)
        #expect(store.state.tokens == [backup])
    }

    @Test
    func aDroppedConnectionKeepsThePassword() async {
        let store = makeStore(configure: { $0.filesClient.createAPIToken = { _, _, _, _, _ in throw FilesClientError.rateLimited } })
        store.exhaustivity = .off

        await store.send(.newTokenTapped)
        await store.send(.nameChanged("ci"))
        await store.send(.passwordChanged("hunter2"))
        await store.send(.createSubmitted)
        await store.receive(\.createResponse)

        #expect(store.state.createForm?.password == "hunter2")
        #expect(store.state.errorMessage == FilesClientError.rateLimited.userMessage)
    }

    @Test
    func submittingTwiceWhileWorkingSendsOnce() async {
        let calls = LockIsolated(0)
        let store = makeStore(
            configure: { $0.filesClient.createAPIToken = { _, _, _, _, _ in calls.withValue { $0 += 1 }; return IssuedAPIToken(token: nightly, secret: "s") } },
            initial: {
                $0.createForm = APITokensFeature.CreateForm(name: "ci", password: "x")
                $0.isWorking = true
            }
        )

        await store.send(.createSubmitted)
        #expect(calls.value == 0)
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
    func dismissingTheSecretForgetsIt() async {
        let store = makeStore(initial: { $0.issued = IssuedAPIToken(token: nightly, secret: "s") })

        await store.send(.issuedDismissed) { $0.issued = nil }
    }

    // MARK: Rename

    @Test
    func renameStartsFromTheCurrentNameAndReplacesTheTokenInPlace() async {
        let renamed = APIToken(id: "t1", name: "weekly", scope: .read, createdAt: backup.createdAt)
        let sent = LockIsolated<[String]>([])
        let store = makeStore(tokens: [backup, nightly], configure: {
            $0.filesClient.renameAPIToken = { _, id, name in sent.setValue([id, name]); return renamed }
        })

        await store.send(.renameTapped(backup)) { $0.rename = .init(id: "t1", name: "backup") }
        await store.send(.renameNameChanged("  weekly ")) { $0.rename?.name = "  weekly " }
        await store.send(.renameSubmitted) { $0.isWorking = true }
        await store.receive(\.renameResponse) {
            $0.isWorking = false
            $0.rename = nil
            $0.tokens = [renamed, nightly]
        }
        #expect(sent.value == ["t1", "weekly"])
    }

    @Test
    func renameIsRefusedForABlankName() async {
        let store = makeStore()
        await store.send(.renameTapped(backup)) { $0.rename = .init(id: "t1", name: "backup") }
        await store.send(.renameNameChanged("  ")) { $0.rename?.name = "  " }
        await store.send(.renameSubmitted)
    }

    @Test
    func aFailedRenameShowsTheMessageAndKeepsTheOldName() async {
        let gone = FilesClientError.serverMessage(statusCode: 404, message: "There is no such token on this account.")
        let store = makeStore(configure: { $0.filesClient.renameAPIToken = { _, _, _ in throw gone } })

        await store.send(.renameTapped(backup)) { $0.rename = .init(id: "t1", name: "backup") }
        await store.send(.renameNameChanged("x")) { $0.rename?.name = "x" }
        await store.send(.renameSubmitted) { $0.isWorking = true }
        await store.receive(\.renameResponse) {
            $0.isWorking = false
            $0.rename = nil
            $0.errorMessage = gone.userMessage
        }
        #expect(store.state.tokens == [backup])
    }

    @Test
    func cancellingARenameClearsIt() async {
        let store = makeStore(initial: { $0.rename = .init(id: "t1", name: "x") })
        await store.send(.renameCancelled) { $0.rename = nil }
    }

    // MARK: Revoke

    @Test
    func revokeAsksFirstAndCancellingChangesNothing() async {
        let store = makeStore(configure: { $0.filesClient.revokeAPIToken = { _, _ in Issue.record("must not revoke") } })

        await store.send(.revokeTapped(backup)) { $0.tokenPendingRevoke = backup }
        await store.send(.revokeCancelled) { $0.tokenPendingRevoke = nil }
        #expect(store.state.tokens == [backup])
    }

    @Test
    func confirmingRevokeSendsTheIdAndRemovesOnlyThatToken() async {
        let sent = LockIsolated<String?>(nil)
        let store = makeStore(tokens: [backup, nightly], configure: { $0.filesClient.revokeAPIToken = { _, id in sent.setValue(id) } })

        await store.send(.revokeTapped(backup)) { $0.tokenPendingRevoke = backup }
        await store.send(.revokeConfirmed) {
            $0.tokenPendingRevoke = nil
            $0.isWorking = true
        }
        await store.receive(\.revokeResponse) {
            $0.isWorking = false
            $0.tokens = [nightly]
        }
        #expect(sent.value == "t1")
    }

    @Test
    func aFailedRevokeKeepsTheTokenAndShowsTheMessage() async {
        let store = makeStore(configure: { $0.filesClient.revokeAPIToken = { _, _ in throw FilesClientError.rateLimited } })

        await store.send(.revokeTapped(backup)) { $0.tokenPendingRevoke = backup }
        await store.send(.revokeConfirmed) {
            $0.tokenPendingRevoke = nil
            $0.isWorking = true
        }
        await store.receive(\.revokeResponse) {
            $0.isWorking = false
            $0.errorMessage = FilesClientError.rateLimited.userMessage
        }
        #expect(store.state.tokens == [backup])
    }

    @Test
    func revokeConfirmedWithNothingPendingDoesNothing() async {
        await makeStore(configure: { $0.filesClient.revokeAPIToken = { _, _ in Issue.record("nothing pending") } }).send(.revokeConfirmed)
    }
}
