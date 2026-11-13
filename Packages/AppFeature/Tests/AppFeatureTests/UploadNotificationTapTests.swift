@testable import AppFeature
import ComposableArchitecture
import CoreModels
import FilesFeature
import Foundation
import Testing
import TestUtils

extension AppSuites {
    /// Tapping an "upload finished" notification opens the folder the files went to, in the account
    /// they were uploaded with.
    @MainActor
    @Suite("Upload notification tap", .isolatedDependencies)
    struct UploadNotificationTapTests {
        private typealias Store = TestStore<AppFeature.State, AppFeature.Action>

        private func tap(_ accountID: String, _ folder: String = TestPath.filesDocuments) -> UploadNotificationTaps.Tap
        {
            UploadNotificationTaps.Tap(accountID: accountID, folder: folder)
        }

        private func signedIn(
            as user: User = AppFixtures.userA,
            on serverURL: URL = AppFixtures.serverA,
            accounts: [AccountSummary],
            pending: AppFeature.PendingUploadFolder? = nil
        ) -> AppFeature.State {
            var state = AppFeature.State(destination: .authenticated(AuthenticatedFeature.State(
                serverURL: serverURL,
                user: user
            )))
            state.$accounts.withLock { $0 = accounts }
            state.pendingUploadFolder = pending
            return state
        }

        private func makeStore(_ state: AppFeature.State) -> Store {
            TestStore(initialState: state) { UploadFolderRouting() }
        }

        @Test("The active account opens the folder right away")
        func activeAccountOpensTheFolder() async {
            let store = makeStore(signedIn(accounts: [AppFixtures.summaryA]))

            await store.send(.uploadNotificationTapped(tap(AppFixtures.accountA)))
            await store.receive(\.destination.authenticated.mainTab.goToFolderRequested, TestPath.filesDocuments)
        }

        @Test("A tap that launches the app keeps the folder while no account is up")
        func coldLaunchKeepsTheFolder() async {
            let store = makeStore(AppFeature.State())

            await store.send(.uploadNotificationTapped(tap(AppFixtures.accountA))) {
                $0.pendingUploadFolder = AppFeature.PendingUploadFolder(tap: tap(AppFixtures.accountA))
            }
        }

        @Test("The kept folder opens once the tabs of its account are up")
        func mountedTabsOpenTheKeptFolder() async {
            let pending = AppFeature.PendingUploadFolder(tap: tap(AppFixtures.accountA))
            let store = makeStore(signedIn(accounts: [AppFixtures.summaryA], pending: pending))

            await store.send(.destination(.authenticated(.mainTab(.observeConnectivity)))) {
                $0.pendingUploadFolder = nil
            }
            await store.receive(\.destination.authenticated.mainTab.goToFolderRequested, TestPath.filesDocuments)
        }

        @Test("Another signed in account is switched to first, then its folder opens")
        func otherAccountIsSwitchedToThenOpens() async {
            let store = makeStore(signedIn(accounts: [AppFixtures.summaryA, AppFixtures.summaryB]))

            await store.send(.uploadNotificationTapped(tap(AppFixtures.accountB, TestFolder.photos))) {
                $0.pendingUploadFolder = AppFeature.PendingUploadFolder(
                    tap: tap(AppFixtures.accountB, TestFolder.photos),
                    hasRequestedSwitch: true
                )
            }
            await store.receive(\.destination.authenticated.mainTab.delegate, .switchAccount(AppFixtures.accountB))

            let switched = makeStore(signedIn(
                as: AppFixtures.userB,
                on: AppFixtures.serverB,
                accounts: [AppFixtures.summaryA, AppFixtures.summaryB],
                pending: store.state.pendingUploadFolder
            ))
            await switched.send(.destination(.authenticated(.mainTab(.observeConnectivity)))) {
                $0.pendingUploadFolder = nil
            }
            await switched.receive(\.destination.authenticated.mainTab.goToFolderRequested, TestFolder.photos)
        }

        @Test("A switch that lands on another account gives up instead of switching again")
        func failedSwitchGivesUp() async {
            let pending = AppFeature.PendingUploadFolder(tap: tap(AppFixtures.accountB), hasRequestedSwitch: true)
            let store = makeStore(signedIn(accounts: [AppFixtures.summaryA, AppFixtures.summaryB], pending: pending))

            await store.send(.destination(.authenticated(.mainTab(.observeConnectivity)))) {
                $0.pendingUploadFolder = nil
            }
        }

        @Test("The app reducer routes a tap through the folder routing")
        func appFeatureRoutesTheTap() async {
            let store = TestStore(initialState: AppFeature.State()) { AppFeature() }

            await store.send(.uploadNotificationTapped(tap(AppFixtures.accountA))) {
                $0.pendingUploadFolder = AppFeature.PendingUploadFolder(tap: tap(AppFixtures.accountA))
            }
        }

        @Test("A signed out account just opens the app")
        func signedOutAccountIsDropped() async {
            let store = makeStore(signedIn(accounts: [AppFixtures.summaryA]))

            await store.send(.uploadNotificationTapped(tap(AppFixtures.accountB, TestFolder.photos)))
        }
    }
}
