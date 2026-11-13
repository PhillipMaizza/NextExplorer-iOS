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
        let expected: SettingsFeature.PasswordStatus?
    }

    @Test(arguments: [
        MethodsCase(
            result: .success([SignInMethod(id: "m1", type: "local_password", provider: "Password")]),
            expected: .present
        ),
        MethodsCase(result: .success([SignInMethod(id: "m2", type: "oidc", provider: "PocketID")]), expected: .absent),
        MethodsCase(result: .success([]), expected: .absent),
        MethodsCase(result: .failure(.server(statusCode: 500)), expected: nil),
    ])
    func theSignInMethodsDecideWhetherTheAccountHasAPassword(_ testCase: MethodsCase) async {
        let store = makeStore()

        if let expected = testCase.expected {
            await store.send(.authMethodsResponse(testCase.result)) { $0.passwordStatus = expected }
        } else {
            await store.send(.authMethodsResponse(testCase.result))
            #expect(store.state.passwordStatus == .unknown)
        }
    }

    struct StatusCase: Sendable {
        let result: Result<AuthStatus, FilesClientError>
        let expected: SettingsFeature.LocalSignInStatus?
    }

    @Test(arguments: [
        StatusCase(result: .success(AuthStatus(localEnabled: true, oidcEnabled: false)), expected: .enabled),
        StatusCase(result: .success(AuthStatus(localEnabled: false, oidcEnabled: true)), expected: .disabled),
        StatusCase(result: .failure(.server(statusCode: 500)), expected: nil),
    ])
    func theServerStatusDecidesWhetherPasswordSignInIsOn(_ testCase: StatusCase) async {
        let store = makeStore()

        if let expected = testCase.expected {
            await store.send(.authStatusResponse(testCase.result)) { $0.localSignInStatus = expected }
        } else {
            await store.send(.authStatusResponse(testCase.result))
            #expect(store.state.localSignInStatus == .unknown)
        }
    }

    struct RowsCase: Sendable {
        let signIn: SettingsFeature.LocalSignInStatus
        let password: SettingsFeature.PasswordStatus
        let showsPassword: Bool
        let showsTwoFactor: Bool
    }

    @Test(arguments: [
        RowsCase(signIn: .unknown, password: .unknown, showsPassword: true, showsTwoFactor: true),
        RowsCase(signIn: .unknown, password: .present, showsPassword: true, showsTwoFactor: true),
        RowsCase(signIn: .unknown, password: .absent, showsPassword: true, showsTwoFactor: false),
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

    @Test
    func theRowsStayVisibleUntilTheStatusArrives() {
        let state = makeState()

        #expect(state.passwordStatus == .unknown)
        #expect(state.localSignInStatus == .unknown)
        #expect(state.showsPasswordRow)
        #expect(state.showsTwoFactorRow)
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
