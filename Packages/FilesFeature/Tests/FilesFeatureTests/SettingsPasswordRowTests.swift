import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SettingsPasswordRowTests: SettingsFeatureTestSupport {
    struct MethodsCase: Sendable {
        let result: Result<[SignInMethod], FilesClientError>
        let expected: SettingsFeature.PasswordStatus
    }

    @Test(arguments: [
        MethodsCase(
            result: .success([SignInMethod(id: "m1", type: "local_password", provider: "Password")]),
            expected: .present
        ),
        MethodsCase(result: .success([SignInMethod(id: "m2", type: "oidc", provider: "PocketID")]), expected: .absent),
        MethodsCase(result: .success([]), expected: .absent),
        MethodsCase(result: .failure(.server(statusCode: 500)), expected: .unconfirmed),
    ])
    func theSignInMethodsDecideWhetherTheAccountHasAPassword(_ testCase: MethodsCase) async {
        let store = makeStore()

        await store.send(.authMethodsResponse(testCase.result)) { $0.passwordStatus = testCase.expected }
    }

    struct StatusCase: Sendable {
        let result: Result<AuthStatus, FilesClientError>
        let expected: SettingsFeature.LocalSignInStatus
    }

    @Test(arguments: [
        StatusCase(result: .success(AuthStatus(localEnabled: true, oidcEnabled: false)), expected: .enabled),
        StatusCase(result: .success(AuthStatus(localEnabled: false, oidcEnabled: true)), expected: .disabled),
        StatusCase(result: .failure(.server(statusCode: 500)), expected: .unconfirmed),
    ])
    func theServerStatusDecidesWhetherPasswordSignInIsOn(_ testCase: StatusCase) async {
        let store = makeStore()

        await store.send(.authStatusResponse(testCase.result)) { $0.localSignInStatus = testCase.expected }
    }

    struct RowsCase: Sendable {
        let signIn: SettingsFeature.LocalSignInStatus
        let password: SettingsFeature.PasswordStatus
        let showsPassword: Bool
        let showsTwoFactor: Bool
    }

    @Test(arguments: [
        RowsCase(signIn: .unknown, password: .unknown, showsPassword: false, showsTwoFactor: false),
        RowsCase(signIn: .unknown, password: .present, showsPassword: false, showsTwoFactor: false),
        RowsCase(signIn: .enabled, password: .unknown, showsPassword: true, showsTwoFactor: false),
        RowsCase(signIn: .unconfirmed, password: .unconfirmed, showsPassword: true, showsTwoFactor: true),
        RowsCase(signIn: .unconfirmed, password: .absent, showsPassword: true, showsTwoFactor: false),
        RowsCase(signIn: .enabled, password: .present, showsPassword: true, showsTwoFactor: true),
        RowsCase(signIn: .enabled, password: .absent, showsPassword: true, showsTwoFactor: false),
        RowsCase(signIn: .disabled, password: .present, showsPassword: false, showsTwoFactor: false),
        RowsCase(signIn: .disabled, password: .absent, showsPassword: false, showsTwoFactor: false),
    ])
    func thePasswordAndTwoFactorRowsFollowTheServerAndTheAccount(_ testCase: RowsCase) {
        var state = makeState()
        state.localSignInStatus = testCase.signIn
        state.passwordStatus = testCase.password

        #expect(state.showsPasswordRow == testCase.showsPassword)
        #expect(state.showsTwoFactorRow == testCase.showsTwoFactor)
    }

    @Test("The sign in rows stay hidden until the server answers, so none shows for a moment")
    func theRowsWaitForTheStatus() {
        let state = makeState()

        #expect(state.passwordStatus == .unknown)
        #expect(state.localSignInStatus == .unknown)
        #expect(!state.showsPasswordRow)
        #expect(!state.showsTwoFactorRow)
    }

    @Test("A failed refetch keeps the answer the server already gave")
    func aFailedRefetchKeepsTheKnownStatus() async {
        var state = makeState()
        state.passwordStatus = .absent
        state.localSignInStatus = .disabled
        let store = makeStore(state: state)

        await store.send(.authMethodsResponse(.failure(.server(statusCode: 500))))
        await store.send(.authStatusResponse(.failure(.server(statusCode: 500))))
    }

    @Test("A menu shown before Settings asks for the sign in rows, until both answers are in")
    func theAccountMenuAsksForTheStatus() async {
        let statusGate = AsyncGate()
        let store = TestStore(initialState: makeState()) { SettingsFeature() } withDependencies: {
            $0.filesClient.fetchAuthMethods = { _ in [] }
            $0.filesClient.fetchAuthStatus = { _ in
                try await statusGate.wait()
                return AuthStatus(localEnabled: true, oidcEnabled: false)
            }
        }

        await store.send(.signInStatusRequested)
        await store.receive(\.authMethodsResponse) { $0.passwordStatus = .absent }
        statusGate.open()
        await store.receive(\.authStatusResponse) { $0.localSignInStatus = .enabled }
        await store.send(.signInStatusRequested)
    }

    @Test(arguments: [
        (SettingsFeature.PasswordStatus.present, ChangePasswordFeature.Mode.change),
        (.absent, .add),
        (.unknown, .change),
    ])
    func theChangePasswordScreenOpensInTheModeTheAccountNeeds(
        status: SettingsFeature.PasswordStatus,
        mode: ChangePasswordFeature.Mode
    ) async {
        var state = makeState()
        state.passwordStatus = status
        let store = makeStore(state: state)

        await store.send(.changePasswordButtonTapped) {
            $0.changePassword = ChangePasswordFeature.State(serverURL: serverURL, mode: mode)
        }
    }

    @Test(arguments: [
        (SettingsFeature.PasswordStatus.present, true),
        (.absent, false),
        (.unknown, true),
    ])
    func aSingleSignOnAccountIsNotAskedForAPasswordToMakeAToken(
        status: SettingsFeature.PasswordStatus,
        requiresPassword: Bool
    ) async {
        var state = makeState()
        state.passwordStatus = status
        let store = makeStore(state: state)

        await store.send(.apiTokensButtonTapped) {
            $0.apiTokens = APITokensFeature.State(serverURL: serverURL, requiresPassword: requiresPassword)
        }
    }

    @Test
    func addingAPasswordClosesTheScreenAndTurnsTheRowIntoChangePassword() async {
        var state = makeState()
        state.passwordStatus = .absent
        state.changePassword = ChangePasswordFeature.State(serverURL: serverURL, mode: .add)
        let store = makeStore(state: state)

        await store.send(.changePassword(.presented(.delegate(.passwordAdded)))) {
            $0.passwordStatus = .present
            $0.changePassword = nil
        }
    }
}
