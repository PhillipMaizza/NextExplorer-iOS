@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing
import TestUtils

extension AppSuites {
    @MainActor
    @Suite("AuthenticatedFeature", .isolatedDependencies)
    struct AuthenticatedFeatureTests {
        private typealias Store = TestStore<AuthenticatedFeature.State, AuthenticatedFeature.Action>

        private enum Constants {
            static let promptDismissDuration: Duration = .seconds(0.4)
        }

        private let credentialsB = AppFixtures.credentials(AppFixtures.serverB, TestUser.bob)
        private let recorder = WipeRecorder()

        private func makeStore(
            _ state: AuthenticatedFeature.State = AuthenticatedFeature.State(serverURL: AppFixtures.serverA, user: AppFixtures.userA),
            clock: TestClock<Duration> = TestClock(),
            configure: (inout DependencyValues) -> Void = { _ in }
        ) -> Store {
            TestStore(initialState: state) {
                AuthenticatedFeature()
            } withDependencies: {
                recorder.install(into: &$0)
                $0.continuousClock = clock
                configure(&$0)
            }
        }

        // MARK: Last account

        @Test("The sign out confirmation closes first, and the login screen is only requested once it has slid away")
        func lastAccountSignOutDismissesThePromptBeforeHandingOff() async {
            let clock = TestClock()
            var state = AuthenticatedFeature.State(serverURL: AppFixtures.serverA, user: AppFixtures.userA)
            state.mainTab.settings.isConfirmingSignOut = true
            let store = makeStore(state, clock: clock)

            await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
                $0.mainTab.settings.isSigningOut = true
            }
            await store.receive(\.accountChangeResolved) {
                $0.mainTab.settings.isConfirmingSignOut = false
            }
            await clock.advance(by: Constants.promptDismissDuration)
            await store.receive(\.delegate.activeAccountChanged, nil)
        }

        @Test("Removing the last account closes its removal prompt before the login screen is requested")
        func lastAccountRemovalDismissesItsPromptBeforeHandingOff() async {
            let clock = TestClock()
            var state = AuthenticatedFeature.State(serverURL: AppFixtures.serverA, user: AppFixtures.userA)
            state.mainTab.settings.accountPendingRemoval = AppFixtures.summaryA
            let store = makeStore(state, clock: clock)

            await store.send(.mainTab(.delegate(.removeAccount(AppFixtures.accountA))))
            await store.receive(\.accountChangeResolved) {
                $0.mainTab.settings.accountPendingRemoval = nil
            }
            await clock.advance(by: Constants.promptDismissDuration)
            await store.receive(\.delegate.activeAccountChanged, nil)
        }

        // MARK: Another account remains

        @Test("Signing out with another account left hands off at once, with no wait for a prompt to close")
        func signOutFallsThroughToNextAccountAtOnce() async {
            let store = makeStore {
                $0.authClient.removeAccount = { [credentialsB] _ in credentialsB }
            }

            await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
                $0.mainTab.settings.isSigningOut = true
            }
            await store.receive(\.accountChangeResolved, credentialsB) {
                $0.mainTab.settings.isSigningOut = false
            }
            await store.receive(\.delegate.activeAccountChanged, credentialsB)
        }

        struct DropTrigger: Sendable {
            let action: AuthenticatedFeature.Action
            let isSignOut: Bool
        }

        nonisolated static let dropTriggers = [
            DropTrigger(action: .mainTab(.delegate(.signOutButtonTapped)), isSignOut: true),
            DropTrigger(action: .mainTab(.delegate(.removeAccount(AppFixtures.accountA))), isSignOut: false),
        ]

        @Test("Dropping the active account clears only that account's caches and keeps the next one's", arguments: dropTriggers)
        func droppingTheActiveAccountClearsOnlyItsCaches(_ trigger: DropTrigger) async {
            let directory = DirectoryCacheStore.inMemory()
            let json = JSONCacheStore.inMemory()
            let browse = BrowseResult(
                items: [],
                access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
                path: ""
            )
            for id in [AppFixtures.accountA, AppFixtures.accountB] {
                directory.bound(to: id).write(serverURL: AppFixtures.serverA, path: "", result: browse, etag: nil, fetchedAt: MockDate.date)
                json.bound(to: id).write(key: TestCacheKey.favorites, data: Data(id.utf8))
            }
            let store = makeStore {
                $0.authClient.removeAccount = { [recorder, credentialsB] id in
                    recorder.record(.accountRemoved(id))
                    return credentialsB
                }
                $0.directoryCacheStore = directory
                $0.jsonCacheStore = json
            }
            let markSigningOut: ((inout AuthenticatedFeature.State) -> Void)? = trigger.isSignOut
                ? { $0.mainTab.settings.isSigningOut = true } : nil
            let markSignedOut: ((inout AuthenticatedFeature.State) -> Void)? = trigger.isSignOut
                ? { $0.mainTab.settings.isSigningOut = false } : nil

            await store.send(trigger.action, assert: markSigningOut)
            await store.receive(\.accountChangeResolved, credentialsB, assert: markSignedOut)
            await store.receive(\.delegate.activeAccountChanged, credentialsB)

            #expect(directory.bound(to: AppFixtures.accountA).read(serverURL: AppFixtures.serverA, path: "") == nil)
            #expect(directory.bound(to: AppFixtures.accountB).read(serverURL: AppFixtures.serverA, path: "") != nil)
            #expect(json.bound(to: AppFixtures.accountA).read(key: TestCacheKey.favorites) == nil)
            #expect(json.bound(to: AppFixtures.accountB).read(key: TestCacheKey.favorites) != nil)
            #expect(
                recorder.events.value == [
                    .accountRemoved(AppFixtures.accountA),
                    .previewAccountCleared(AppFixtures.accountA),
                    .offlineAccountCleared(AppFixtures.accountA),
                    .thumbnailMemoryCleared,
                ],
                "the account is removed from the keychain before its caches go, and the next account's stay"
            )
        }

        // MARK: Switching and adding

        @Test("Switching account performs the switch and delegates the new active account")
        func switchAccount() async {
            let requestedID = LockIsolated<String?>(nil)
            let store = makeStore {
                $0.authClient.switchAccount = { [credentialsB] id in
                    requestedID.setValue(id)
                    return credentialsB
                }
            }

            await store.send(.mainTab(.delegate(.switchAccount(AppFixtures.accountB))))
            await store.receive(\.accountChangeResolved, credentialsB)
            await store.receive(\.delegate.activeAccountChanged, credentialsB)

            #expect(requestedID.value == "https://b.example.com|bob")
            #expect(recorder.events.value.isEmpty, "switching wipes nothing")
        }

        @Test("An add account request bubbles straight up to the parent")
        func addAccountRequestBubbles() async {
            let store = makeStore()

            await store.send(.mainTab(.delegate(.addAccountRequested)))
            await store.receive(\.delegate.addAccountRequested)
        }
    }
}
