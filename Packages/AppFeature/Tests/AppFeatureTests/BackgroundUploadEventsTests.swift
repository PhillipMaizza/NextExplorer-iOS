@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
import ShareUploads
import Testing
import TestUtils

@Suite("Background upload events")
struct BackgroundUploadEventsTests {
    private let server = URL(string: TestHost.serverURLString) ?? URL(fileURLWithPath: "/")

    private func credentials(username: String) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: server, authMode: .local, cookieName: TestSession.cookieName, cookieValue: TestSession.cookieValue,
            cookieDomain: TestHost.server, cookiePath: "/", cookieIsSecure: true, expiresAt: nil, username: username
        )
    }

    private func authClient(
        active: String?, sessions: [SessionCredentials], me: @escaping @Sendable (URL) async throws -> User
    ) -> AuthClient {
        var client = AuthClient()
        client.me = me
        client.listSessions = { sessions }
        client.activeAccountID = { active }
        return client
    }

    private func shareUploads(
        flagged: Set<String>,
        cleared: LockIsolated<[String]>,
        retried: LockIsolated<[SessionCredentials]> = LockIsolated([])
    ) -> ShareUploadsClient {
        ShareUploadsClient(
            cancel: { _ in },
            accountsNeedingSignIn: { flagged },
            clearNeedsSignIn: { id in cleared.withValue { $0.append(id) } },
            retryRefused: { credentials in
                retried.withValue { $0.append(credentials) }
                return 1
            }
        )
    }

    private let user = User(id: "1", username: TestAccount.username, email: nil, roles: [])

    @Test("A flagged active account whose session the server still rejects trips the session expired path")
    func rejectedSessionExpires() async {
        let account = credentials(username: TestAccount.username)
        let cleared = LockIsolated<[String]>([])
        let expired = LockIsolated(0)

        await BackgroundUploadEvents.checkRefusedSessions(
            shareUploads: shareUploads(flagged: [account.accountID], cleared: cleared),
            authClient: authClient(active: account.accountID, sessions: [account], me: { _ in throw AuthClientError.sessionExpired }),
            expireSession: { expired.withValue { $0 += 1 } }
        )

        #expect(expired.value == 1)
        #expect(cleared.value == [account.accountID])
    }

    @Test("A session the server still rejects, or cannot answer for, retries nothing")
    func noRetryWithoutAWorkingSession() async {
        let account = credentials(username: TestAccount.username)
        for failure in [AuthClientError.sessionExpired, .network(TestFailure.offline)] {
            let retried = LockIsolated<[SessionCredentials]>([])

            await BackgroundUploadEvents.checkRefusedSessions(
                shareUploads: shareUploads(flagged: [account.accountID], cleared: LockIsolated([]), retried: retried),
                authClient: authClient(active: account.accountID, sessions: [account], me: { _ in throw failure }),
                expireSession: {}
            )

            #expect(retried.value.isEmpty, "\(failure)")
        }
    }

    @Test("A 401 from the server counts as a rejected session too")
    func serverFourOhOneExpires() async {
        let account = credentials(username: TestAccount.username)
        let expired = LockIsolated(0)

        await BackgroundUploadEvents.checkRefusedSessions(
            shareUploads: shareUploads(flagged: [account.accountID], cleared: LockIsolated([])),
            authClient: authClient(active: account.accountID, sessions: [account], me: { _ in throw AuthClientError.server(statusCode: 401) }),
            expireSession: { expired.withValue { $0 += 1 } }
        )

        #expect(expired.value == 1)
    }

    @Test("A stale flag (the session works again) is cleared without signing the user out")
    func staleFlagIsCleared() async {
        let account = credentials(username: TestAccount.username)
        let cleared = LockIsolated<[String]>([])
        let retried = LockIsolated<[SessionCredentials]>([])
        let expired = LockIsolated(0)
        let signedIn = user

        await BackgroundUploadEvents.checkRefusedSessions(
            shareUploads: shareUploads(flagged: [account.accountID], cleared: cleared, retried: retried),
            authClient: authClient(active: account.accountID, sessions: [account], me: { _ in signedIn }),
            expireSession: { expired.withValue { $0 += 1 } }
        )

        #expect(expired.value == 0)
        #expect(cleared.value == [account.accountID])
        #expect(retried.value == [account], "the files the server refused go out again now that the session works")
    }

    @Test("A server that cannot be reached neither signs out nor forgets the flag")
    func unreachableServerKeepsTheFlag() async {
        let account = credentials(username: TestAccount.username)
        let cleared = LockIsolated<[String]>([])
        let expired = LockIsolated(0)

        await BackgroundUploadEvents.checkRefusedSessions(
            shareUploads: shareUploads(flagged: [account.accountID], cleared: cleared),
            authClient: authClient(active: account.accountID, sessions: [account], me: { _ in throw AuthClientError.network(TestFailure.offline) }),
            expireSession: { expired.withValue { $0 += 1 } }
        )

        #expect(expired.value == 0)
        #expect(cleared.value.isEmpty)
    }

    @Test("A flag for another account, or no flag, does nothing")
    func otherAccountIsIgnored() async {
        let account = credentials(username: TestAccount.username)
        let asked = LockIsolated(0)
        let expired = LockIsolated(0)
        let signedIn = user
        let client = authClient(active: account.accountID, sessions: [account], me: { _ in
            asked.withValue { $0 += 1 }
            return signedIn
        })

        await BackgroundUploadEvents.checkRefusedSessions(
            shareUploads: shareUploads(flagged: ["someone|else"], cleared: LockIsolated([])),
            authClient: client,
            expireSession: { expired.withValue { $0 += 1 } }
        )
        await BackgroundUploadEvents.checkRefusedSessions(
            shareUploads: shareUploads(flagged: [], cleared: LockIsolated([])),
            authClient: client,
            expireSession: { expired.withValue { $0 += 1 } }
        )

        #expect(asked.value == 0, "no request is made for an account nothing flagged")
        #expect(expired.value == 0)
    }

    private func retry(
        accountID: String?, sessions: [SessionCredentials], retried: Int,
        received: LockIsolated<[(String, SessionCredentials)]> = LockIsolated([]),
        notices: LockIsolated<[UploadNotifications.RetryFailure]>
    ) async {
        let signedIn = user
        await BackgroundUploadEvents.retry(
            batchID: TestUpload.batchID,
            authClient: authClient(active: nil, sessions: sessions, me: { _ in signedIn }),
            accountID: { _ in accountID },
            retryFailed: { batchID, credentials in
                received.withValue { $0.append((batchID, credentials)) }
                return retried
            },
            notifyFailure: { reason in notices.withValue { $0.append(reason) } }
        )
    }

    @Test("Retry resends with the batch account's current credentials and stays quiet")
    func retryUsesCurrentCredentials() async {
        let account = credentials(username: TestAccount.username)
        let received = LockIsolated<[(String, SessionCredentials)]>([])
        let notices = LockIsolated<[UploadNotifications.RetryFailure]>([])

        await retry(accountID: account.accountID, sessions: [account], retried: 1, received: received, notices: notices)

        #expect(received.value.count == 1)
        #expect(received.value.first?.0 == TestUpload.batchID)
        #expect(received.value.first?.1 == account)
        #expect(notices.value.isEmpty)
    }

    @Test("Retry tells the user when the account is no longer signed in")
    func retryNeedsASession() async {
        let received = LockIsolated<[(String, SessionCredentials)]>([])
        let notices = LockIsolated<[UploadNotifications.RetryFailure]>([])

        await retry(accountID: "gone|nobody", sessions: [], retried: 0, received: received, notices: notices)

        #expect(received.value.isEmpty)
        #expect(notices.value == [.needsSignIn], "the files are still on disk: sign in and tap Retry again, not share again")
    }

    @Test("Retry tells the user when the batch is gone, so no account can be found for it")
    func retryWithoutABatch() async {
        let account = credentials(username: TestAccount.username)
        let received = LockIsolated<[(String, SessionCredentials)]>([])
        let notices = LockIsolated<[UploadNotifications.RetryFailure]>([])

        await retry(accountID: nil, sessions: [account], retried: 1, received: received, notices: notices)

        #expect(received.value.isEmpty)
        #expect(notices.value == [.nothingToSend])
    }

    @Test("Retry tells the user when no failed file was left to send")
    func retrySendingNothing() async {
        let account = credentials(username: TestAccount.username)
        let notices = LockIsolated<[UploadNotifications.RetryFailure]>([])

        await retry(accountID: account.accountID, sessions: [account], retried: 0, notices: notices)

        #expect(notices.value == [.nothingToSend])
    }

    // MARK: Reconnecting

    @Test("Nothing is read from the keychain while no batch is pending")
    func idleReconnectReadsNoSessions() async {
        let loaded = LockIsolated(0)
        let reconnected = LockIsolated(0)

        await BackgroundUploadEvents.reconnectPending(
            hasPending: { false },
            sessions: {
                loaded.withValue { $0 += 1 }
                return []
            },
            reconnect: { _ in reconnected.withValue { $0 += 1 } }
        )

        #expect(loaded.value == 0)
        #expect(reconnected.value == 0)
    }

    @Test("A pending batch is reconnected with the signed in sessions")
    func pendingReconnectsWithSessions() async {
        let account = credentials(username: TestAccount.username)
        let received = LockIsolated<[[SessionCredentials]]>([])

        await BackgroundUploadEvents.reconnectPending(
            hasPending: { true },
            sessions: { [account] },
            reconnect: { sessions in received.withValue { $0.append(sessions) } }
        )

        #expect(received.value == [[account]])
    }

    // MARK: The periodic reconnect

    private let interval: Duration = .seconds(30)
    /// A test clock keeps a sleep whose deadline equals its time asleep, so a loop that reaches its
    /// sleep after the test advanced exactly to the beat would wait forever. Every step lands just
    /// past the beat: a late sleep then returns at once, and the step before still proves nothing
    /// fires early.
    private let pastTheBeat: Duration = .nanoseconds(1)

    @Test("The periodic task fires once per interval, and only after the interval has passed", .timeLimit(.minutes(1)))
    func periodicFiresEachInterval() async {
        let clock = TestClock()
        let task = PeriodicTask()
        let fires = LockIsolated(0)
        let (fired, report) = AsyncStream.makeStream(of: Void.self)
        task.start(every: interval, clock: clock) {
            fires.withValue { $0 += 1 }
            report.yield()
        }
        var iterator = fired.makeAsyncIterator()

        await clock.advance(by: interval - .seconds(1))
        #expect(fires.value == 0, "nothing before the interval")
        await clock.advance(by: .seconds(1) + pastTheBeat)
        await iterator.next()
        #expect(fires.value == 1)
        await clock.advance(by: interval)
        await iterator.next()
        #expect(fires.value == 2)
        task.stop()
    }

    @Test("Starting twice keeps the one timer, so a batch is never reconnected twice per interval")
    func periodicIsIdempotent() async {
        let clock = TestClock()
        let task = PeriodicTask()
        let (fired, report) = AsyncStream.makeStream(of: Int.self)

        #expect(task.start(every: interval, clock: clock) { report.yield(1) })
        #expect(!task.start(every: interval, clock: clock) { report.yield(2) })
        #expect(task.isRunning)
        await clock.advance(by: interval + pastTheBeat)
        var iterator = fired.makeAsyncIterator()
        #expect(await iterator.next() == 1, "only the first timer exists")
        task.stop()
    }

    @Test("Stopping cancels the timer: nothing fires afterwards, and it can be started again")
    func periodicStops() async {
        let clock = TestClock()
        let task = PeriodicTask()
        let fires = LockIsolated(0)
        task.start(every: interval, clock: clock) { fires.withValue { $0 += 1 } }

        task.stop()
        #expect(!task.isRunning)
        await clock.advance(by: interval * 3)
        #expect(fires.value == 0)

        let (fired, report) = AsyncStream.makeStream(of: Void.self)
        #expect(task.start(every: interval, clock: clock) { report.yield() })
        await clock.advance(by: interval + pastTheBeat)
        var iterator = fired.makeAsyncIterator()
        await iterator.next()
        task.stop()
    }

    @Test("The next beat is one interval on, wherever the slow work before it ended")
    func theNextBeatKeepsTheSchedule() {
        let start = TestClock().now
        let beat = start.advanced(by: interval)

        let afterQuickWork = PeriodicTask.beat(after: beat, every: interval, now: beat.advanced(by: .seconds(1)))
        let afterSlowWork = PeriodicTask.beat(after: beat, every: interval, now: beat.advanced(by: .seconds(45)))

        #expect(afterQuickWork == start.advanced(by: .seconds(60)))
        #expect(afterSlowWork == start.advanced(by: .seconds(60)))
    }

    @Test("More than a whole interval behind, the missed beats are skipped instead of fired in a burst")
    func missedBeatsAreSkipped() {
        let start = TestClock().now
        let beat = start.advanced(by: interval)
        let woke = beat.advanced(by: .seconds(600))

        #expect(PeriodicTask.beat(after: beat, every: interval, now: woke) == woke.advanced(by: interval))
    }
}
