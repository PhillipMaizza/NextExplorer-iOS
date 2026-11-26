@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
import Testing
import TestUtils

extension AppSuites {
    @MainActor
    @Suite("Account work boundary", .isolatedDependencies)
    struct AccountWorkBoundaryTests {
        private let credentialsB = AppFixtures.credentials(AppFixtures.serverB, TestUser.bob)
        private let recorder = WipeRecorder()

        @Test("A request the left account started never answers into the account switched to, nor its branding")
        func leftAccountAnswerNeverReachesTheNewAccount() async {
            let trash = AsyncGate()
            let confirmation = AsyncGate()
            let accountList = AsyncGate()
            let store = TestStore(
                initialState: AppFeature.State(destination: .authenticated(
                    AuthenticatedFeature.State(serverURL: AppFixtures.serverA, user: AppFixtures.userA)
                ))
            ) {
                AppFeature()
            } withDependencies: { [credentialsB] in
                recorder.install(into: &$0)
                $0.filesClient.fetchTrash = { _ in
                    try await trash.wait()
                    return TrashListing(isEnabled: true, retentionDays: 30, items: [])
                }
                $0.authClient.me = { _ in
                    try await confirmation.wait()
                    return AppFixtures.userB
                }
                $0.authClient.listSessions = { [credentialsB] in
                    try? await accountList.wait()
                    return [credentialsB]
                }
                $0.authClient.listSessionsOrThrow = { [] }
                $0.authClient.activeAccountID = { AppFixtures.accountB }
            }

            @Shared(.inMemory(Branding.sharedKey)) var branding = Branding()
            $branding.withLock { $0 = Branding(appName: "Acme Files") }

            await store.send(.destination(.authenticated(.mainTab(.trash(.task))))) {
                $0.destination.modify(\.authenticated) { $0.mainTab.trash.phase = .loading }
            }
            await store.send(.activateAccount(credentialsB)) {
                $0.destination = AppFixtures.optimistic(AppFixtures.serverB, username: TestUser.bob)
                $0.destination.modify(\.authenticated) { $0.mainTab.settings.$branding.withLock { $0 = Branding() } }
            }
            await store.receive(\.destination.authenticated.mainTab.offline.accountDeactivated, AppFixtures.accountA)
            await store.receive(\.destination.authenticated.mainTab.downloadQueue.accountLeft)
            accountList.open()
            await store.receive(\.accountsRefreshed) {
                $0.$accounts.withLock { $0 = [AppFixtures.summaryB] }
            }
            trash.open()
            confirmation.open()
            await store.receive(\.sessionValidationResponse) {
                $0.$downloadScope.withLock { $0 = AppFixtures.downloadScopeB }
                $0.destination = AppFixtures.confirmed(AppFixtures.serverB, AppFixtures.userB)
            }
            await store.receive(\.accountsRefreshed)
            await store.finish()

            #expect(branding == Branding())
        }
    }
}
