@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import FilesFeature
import Foundation
import Testing

/// Tapping an "upload finished" notification opens the folder the files went to, in the account
/// they were uploaded with.
@MainActor
@Suite("Upload notification tap", .serialized)
struct UploadNotificationTapTests {
    private let serverA = URL(string: "https://a.example.com") ?? URL(fileURLWithPath: "/")
    private let serverB = URL(string: "https://b.example.com") ?? URL(fileURLWithPath: "/")
    private let alice = User(id: "1", username: "alice", email: nil, roles: [])

    private var accountA: String {
        AuthenticatedFeature.State.accountID(serverURL: serverA, username: "alice")
    }

    private var accountB: String {
        AuthenticatedFeature.State.accountID(serverURL: serverB, username: "bob")
    }

    private func signedIn(accounts: [String]) -> AppFeature.State {
        @Shared(.inMemory(AccountSummary.sharedKey)) var summaries: [AccountSummary] = []
        $summaries.withLock {
            $0 = accounts.map { AccountSummary(id: $0, username: "", serverURL: serverA, isActive: $0 == accountA) }
        }
        return AppFeature.State(destination: .authenticated(AuthenticatedFeature.State(serverURL: serverA, user: alice)))
    }

    @Test("The active account opens the folder right away")
    func activeAccountOpensTheFolder() async {
        let store = TestStore(initialState: signedIn(accounts: [accountA])) { AppFeature() }
        store.exhaustivity = .off

        await store.send(.uploadNotificationTapped(.init(accountID: accountA, folder: "Files/Documents")))
        await store.receive(\.destination.authenticated.mainTab.goToFolderRequested)
        #expect(store.state.pendingUploadFolder == nil)
    }

    @Test("A tap that launches the app keeps the folder until the tabs of its account are up")
    func coldLaunchKeepsTheFolder() async {
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        store.exhaustivity = .off

        await store.send(.uploadNotificationTapped(.init(accountID: accountA, folder: "Files/Documents")))
        #expect(store.state.pendingUploadFolder?.tap.folder == "Files/Documents")

        // Signed in to that account and its tabs mounted: the folder opens.
        store.exhaustivity = .off(showSkippedAssertions: false)
        var state = signedIn(accounts: [accountA])
        state.pendingUploadFolder = store.state.pendingUploadFolder
        let mounted = TestStore(initialState: state) { AppFeature() }
        mounted.exhaustivity = .off
        await mounted.send(.destination(.authenticated(.mainTab(.observeConnectivity))))
        await mounted.receive(\.destination.authenticated.mainTab.goToFolderRequested)
        #expect(mounted.state.pendingUploadFolder == nil)
        await mounted.skipInFlightEffects()
    }

    @Test("Another signed in account is switched to first")
    func otherAccountIsSwitchedTo() async {
        let requested = LockIsolated<String?>(nil)
        let store = TestStore(initialState: signedIn(accounts: [accountA, accountB])) {
            AppFeature()
        } withDependencies: {
            // The switch itself is AuthenticatedFeature's; stop it here, after it was asked for.
            $0.continuousClock = ImmediateClock()
            $0.authClient.switchAccount = { accountID in
                requested.setValue(accountID)
                return nil
            }
        }
        store.exhaustivity = .off

        await store.send(.uploadNotificationTapped(.init(accountID: accountB, folder: "Photos")))
        await store.receive(\.destination.authenticated.mainTab.delegate)
        await store.finish()
        #expect(requested.value == accountB)
        #expect(store.state.pendingUploadFolder?.hasRequestedSwitch == true)
    }

    @Test("A signed out account just opens the app")
    func signedOutAccountIsDropped() async {
        let store = TestStore(initialState: signedIn(accounts: [accountA])) { AppFeature() }
        store.exhaustivity = .off

        await store.send(.uploadNotificationTapped(.init(accountID: accountB, folder: "Photos")))
        #expect(store.state.pendingUploadFolder == nil)
    }
}
