@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("Require sign in")
struct RequireSignInTests {
    private func credentials(_ server: String, _ username: String) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: URL(string: server) ?? URL(fileURLWithPath: "/"),
            authMode: .local,
            cookieName: TestSession.cookieName,
            cookieValue: TestSession.cookieValue,
            cookieDomain: URL(string: server)?.host ?? "",
            cookiePath: "/",
            isCookieSecure: true,
            expiresAt: nil,
            username: username
        )
    }

    @Test("A session saved before sign in could be required loads with no policy and unlocked")
    func oldSessionDecodes() throws {
        let credentials = try CoreModelsFixture.sessionCredentialsSavedWithoutEmail.decode(SessionCredentials.self)
        #expect(credentials.requireSignIn == nil)
        #expect(!credentials.isLocked)
    }

    @Test("A locked session keeps its policy, drops its cookie and survives a save")
    func lockedRoundTrips() throws {
        var session = credentials(TestHost.firstServerURLString, TestUser.alice)
        session.requireSignIn = RequireSignIn(lockAfter: .fiveMinutes, shouldKeepOfflineFiles: false)
        let locked = session.locked
        #expect(locked.cookieValue.isEmpty)
        #expect(locked.isLocked)
        let decoded = try JSONDecoder().decode(SessionCredentials.self, from: JSONEncoder().encode(locked))
        #expect(decoded == locked)
    }

    @Test("Locking locks only the matching unlocked accounts and returns them as they were")
    func lockWhere() {
        var stored = StoredSessions()
        var alice = credentials(TestHost.firstServerURLString, TestUser.alice)
        alice.requireSignIn = RequireSignIn()
        let bob = credentials(TestHost.secondServerURLString, TestUser.bob)
        stored.upsert(alice)
        stored.upsert(bob)

        let unlocked = stored.lock { $0.requireSignIn != nil }

        #expect(unlocked == [alice])
        #expect(stored.sessions.map(\.isLocked) == [true, false])
        #expect(stored.lock { $0.requireSignIn != nil }.isEmpty, "an account already locked is not locked twice")
    }

    @Test("Signing in again keeps the account's policy and unlocks it")
    func upsertKeepsPolicy() {
        var stored = StoredSessions()
        var alice = credentials(TestHost.firstServerURLString, TestUser.alice)
        alice.requireSignIn = RequireSignIn(lockAfter: .immediately)
        stored.upsert(alice)
        _ = stored.lock { _ in true }

        stored.upsert(credentials(TestHost.firstServerURLString, TestUser.alice))

        #expect(stored.active?.requireSignIn == RequireSignIn(lockAfter: .immediately))
        #expect(stored.active?.isLocked == false)
    }

    @Test("Turning the policy off clears it on that account only")
    func setPolicy() {
        var stored = StoredSessions()
        var alice = credentials(TestHost.firstServerURLString, TestUser.alice)
        alice.requireSignIn = RequireSignIn()
        var bob = credentials(TestHost.secondServerURLString, TestUser.bob)
        bob.requireSignIn = RequireSignIn()
        stored.upsert(alice)
        stored.upsert(bob)

        stored.setRequireSignIn(nil, id: alice.accountID)

        #expect(stored.sessions.map(\.requireSignIn) == [nil, RequireSignIn()])
    }

    @Test(
        "Each lock time locks once the time away reaches it, and app start never locks on return",
        arguments: [
            (RequireSignIn.LockAfter.appStart, Duration.seconds(3600), false),
            (.immediately, .zero, true),
            (.thirtySeconds, .seconds(29), false),
            (.thirtySeconds, .seconds(30), true),
            (.oneMinute, .seconds(59), false),
            (.oneMinute, .seconds(60), true),
            (.fiveMinutes, .seconds(299), false),
            (.fiveMinutes, .seconds(300), true)
        ]
    )
    func locksAfter(lockAfter: RequireSignIn.LockAfter, away: Duration, shouldLock: Bool) {
        #expect(lockAfter.locks(after: away) == shouldLock)
    }
}
