@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
import ShareUploads
import Testing

@Suite("Background upload events", .serialized)
struct BackgroundUploadEventsTests {
    private let server = URL(string: "https://files.example.com") ?? URL(fileURLWithPath: "/")

    private func credentials(username: String) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: server, authMode: .local, cookieName: "connect.sid", cookieValue: "abc",
            cookieDomain: "files.example.com", cookiePath: "/", cookieIsSecure: true, expiresAt: nil, username: username
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

    private func shareUploads(flagged: Set<String>, cleared: LockIsolated<[String]>) -> ShareUploadsClient {
        ShareUploadsClient(
            cancel: { _ in },
            accountsNeedingSignIn: { flagged },
            clearNeedsSignIn: { id in cleared.withValue { $0.append(id) } }
        )
    }

    private let user = User(id: "1", username: "phillip", email: nil, roles: [])

    @Test("A flagged active account whose session the server still rejects trips the session expired path")
    func rejectedSessionExpires() async {
        let account = credentials(username: "phillip")
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

    @Test("A 401 from the server counts as a rejected session too")
    func serverFourOhOneExpires() async {
        let account = credentials(username: "phillip")
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
        let account = credentials(username: "phillip")
        let cleared = LockIsolated<[String]>([])
        let expired = LockIsolated(0)
        let signedIn = user

        await BackgroundUploadEvents.checkRefusedSessions(
            shareUploads: shareUploads(flagged: [account.accountID], cleared: cleared),
            authClient: authClient(active: account.accountID, sessions: [account], me: { _ in signedIn }),
            expireSession: { expired.withValue { $0 += 1 } }
        )

        #expect(expired.value == 0)
        #expect(cleared.value == [account.accountID])
    }

    @Test("A server that cannot be reached neither signs out nor forgets the flag")
    func unreachableServerKeepsTheFlag() async {
        let account = credentials(username: "phillip")
        let cleared = LockIsolated<[String]>([])
        let expired = LockIsolated(0)

        await BackgroundUploadEvents.checkRefusedSessions(
            shareUploads: shareUploads(flagged: [account.accountID], cleared: cleared),
            authClient: authClient(active: account.accountID, sessions: [account], me: { _ in throw AuthClientError.network("offline") }),
            expireSession: { expired.withValue { $0 += 1 } }
        )

        #expect(expired.value == 0)
        #expect(cleared.value.isEmpty)
    }

    @Test("A flag for another account, or no flag, does nothing")
    func otherAccountIsIgnored() async {
        let account = credentials(username: "phillip")
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
        received: LockIsolated<[(String, SessionCredentials)]> = LockIsolated([]), notices: LockIsolated<Int>
    ) async {
        let signedIn = user
        await BackgroundUploadEvents.retry(
            batchID: "BATCH",
            authClient: authClient(active: nil, sessions: sessions, me: { _ in signedIn }),
            accountID: { _ in accountID },
            retryFailed: { batchID, credentials in
                received.withValue { $0.append((batchID, credentials)) }
                return retried
            },
            notifyFailure: { notices.withValue { $0 += 1 } }
        )
    }

    @Test("Retry resends with the batch account's current credentials and stays quiet")
    func retryUsesCurrentCredentials() async {
        let account = credentials(username: "phillip")
        let received = LockIsolated<[(String, SessionCredentials)]>([])
        let notices = LockIsolated(0)

        await retry(accountID: account.accountID, sessions: [account], retried: 1, received: received, notices: notices)

        #expect(received.value.count == 1)
        #expect(received.value.first?.0 == "BATCH")
        #expect(received.value.first?.1 == account)
        #expect(notices.value == 0)
    }

    @Test("Retry tells the user when the account is no longer signed in")
    func retryNeedsASession() async {
        let received = LockIsolated<[(String, SessionCredentials)]>([])
        let notices = LockIsolated(0)

        await retry(accountID: "gone|nobody", sessions: [], retried: 0, received: received, notices: notices)

        #expect(received.value.isEmpty)
        #expect(notices.value == 1)
    }

    @Test("Retry tells the user when the batch is gone, so no account can be found for it")
    func retryWithoutABatch() async {
        let account = credentials(username: "phillip")
        let received = LockIsolated<[(String, SessionCredentials)]>([])
        let notices = LockIsolated(0)

        await retry(accountID: nil, sessions: [account], retried: 1, received: received, notices: notices)

        #expect(received.value.isEmpty)
        #expect(notices.value == 1)
    }

    @Test("Retry tells the user when no failed file was left to send")
    func retrySendingNothing() async {
        let account = credentials(username: "phillip")
        let notices = LockIsolated(0)

        await retry(accountID: account.accountID, sessions: [account], retried: 0, notices: notices)

        #expect(notices.value == 1)
    }
}
