import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SettingsRequireSignInTests: SettingsFeatureTestSupport {
    @Test("Turning require sign in on, changing it and off updates the active account and asks the app to store it")
    func requireSignInChanges() async {
        let state = makeState()
        let accountID = SessionCredentials.accountID(serverURL: serverURL, username: user.username)
        state.$accounts.withLock { [serverURL, user] in
            $0 = [AccountSummary(id: accountID, username: user.username, serverURL: serverURL, isActive: true)]
        }
        let store = makeStore(state: state)
        let quick = RequireSignIn(lockAfter: .immediately, shouldKeepOfflineFiles: false)

        for policy in [RequireSignIn(), quick, nil] {
            await store.send(.requireSignInChanged(policy)) {
                $0.$accounts.withLock { $0[0].requireSignIn = policy }
            }
            await store.receive(\.delegate, .requireSignInChanged(accountID: accountID, policy))
        }
    }
}
