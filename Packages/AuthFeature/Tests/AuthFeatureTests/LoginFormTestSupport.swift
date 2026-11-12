import AuthClient
@testable import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Testing
import TestUtils

/// Shared setup for the login form reducer suites: one store builder, one signed in state and the
/// exact log entry shape, so no suite repeats them.
@MainActor
enum LoginFormTestSupport {
    typealias Store = TestStore<LoginFormFeature.State, LoginFormFeature.Action>

    nonisolated static let host = TestHost.nextExplorer
    nonisolated static let serverURL = TestHost.nextExplorerURLString
    nonisolated static let passwordOnly = AuthStatus(localEnabled: true, oidcEnabled: false)

    static func makeStore(
        _ state: LoginFormFeature.State,
        clock: TestClock<Duration>,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> Store {
        TestStore(initialState: state) {
            LoginFormFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.loginLogDate = { MockDate.date }
            configure(&$0)
        }
    }

    /// The credentials page of a server that was tested and offers password sign in.
    static func credentialsState(identifier: String = TestUser.asmith, password: String = TestAccount.password) -> LoginFormFeature.State {
        LoginFormFeature.State(
            currentPage: .credentials,
            host: host,
            identifier: identifier,
            password: password,
            authStatus: passwordOnly
        )
    }

    /// Lets a sign in that succeeds run its minimum spinner time and its success beat, then expects
    /// the hand off to the app.
    static func finishSuccessfulSubmit(_ store: Store, clock: TestClock<Duration>, user: User) async throws {
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.submitSucceeded) { $0.submitPhase = .success }
        await clock.advance(by: .seconds(0.5))
        try await store.receive(.delegate(.authenticated(user, url(serverURL))))
    }

    /// Waits out the failure beat and the error dismissal of a failed sign in.
    static func expireSubmitError(_ store: Store, clock: TestClock<Duration>) async {
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertSubmitToIdle) { $0.submitPhase = .idle }
        await clock.advance(by: .seconds(3))
        await store.receive(\.clearErrorMessage) {
            $0.errorMessage = nil
            $0.invalidFieldsScope = nil
        }
    }

    static func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    static func entry(_ text: String, isProblem: Bool = false) -> LoginDiagnostics.Entry {
        LoginDiagnostics.Entry(timestamp: MockDate.date, text: text, isProblem: isProblem)
    }
}
