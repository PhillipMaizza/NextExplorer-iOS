import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SettingsAccountRowsTests {
    private func state(username: String = TestAccount.username, email: String? = TestAccount.email) -> SettingsFeature
        .State
    {
        SettingsFeature.State(
            serverURL: SettingsTestSupport.serverURL,
            user: User(id: "u1", username: username, email: email)
        )
    }

    private func account(isActive: Bool, serverURL: URL, email: String? = nil) -> AccountSummary {
        AccountSummary(
            id: serverURL.absoluteString + "|",
            username: "",
            serverURL: serverURL,
            isActive: isActive,
            email: email
        )
    }

    @Test
    func beforeTheListLoadsTheSignedInUserIsTheOnlyActiveRow() {
        let rows = state(username: "", email: TestAccount.email).accountRows
        #expect(rows.count == 1)
        #expect(rows.first?.isActive == true)
        #expect(rows.first?.displayName == TestAccount.email)
    }

    @Test
    func theActiveRowShowsTheCurrentEmailAndOthersKeepTheirOwn() throws {
        let otherServerURL = try #require(URL(string: "https://\(TestHost.serverWithPort)"))
        let state = state()
        state.$accounts.withLock {
            $0 = [
                account(isActive: true, serverURL: SettingsTestSupport.serverURL, email: "old@example.com"),
                account(isActive: false, serverURL: otherServerURL),
            ]
        }
        let rows = state.accountRows
        #expect(rows[0].displayName == TestAccount.email)
        #expect(rows[1].displayName == TestHost.serverWithPort)
        #expect(state.activeAccount.displayName == TestAccount.email)
    }

    @Test
    func theActiveRowKeepsItsSavedEmailWhenTheUserHasNone() {
        let state = state(email: nil)
        state.$accounts.withLock {
            $0 = [account(isActive: true, serverURL: SettingsTestSupport.serverURL, email: TestAccount.email)]
        }
        #expect(state.activeAccount.displayName == TestAccount.email)
    }
}
