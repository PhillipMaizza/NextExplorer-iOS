import Foundation
import Keychain
@testable import NetworkClient
import Testing
import TestUtils

@Suite("URLSessionAuthDelegate")
struct AuthDelegateTests {
    private struct RecordingEvaluator: ServerTrustEvaluating {
        let calls: LockIsolatedBox<Int>

        func evaluate(_: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            calls.withValue { $0 += 1 }
            return (.cancelAuthenticationChallenge, nil)
        }
    }

    private func makeDelegate(store: ClientIdentityStore, calls: LockIsolatedBox<Int>) -> URLSessionAuthDelegate {
        URLSessionAuthDelegate(
            trustEvaluator: RecordingEvaluator(calls: calls),
            certificates: ClientCertificateChallengeHandler(store: store)
        )
    }

    private func makeSessionAndTask() -> (URLSession, URLSessionTask) {
        let session = URLSession(configuration: .ephemeral)
        return (session, session.dataTask(with: TestHost.serverURL))
    }

    @Test("the default evaluator leaves server trust to the system")
    func defaultEvaluatorDefersToSystem() async {
        let challenge = ClientCertificateChallengeFixture.make(host: TestHost.server, port: 443, method: NSURLAuthenticationMethodServerTrust)
        let (disposition, credential) = await DefaultServerTrustEvaluator().evaluate(challenge)
        #expect(disposition == .performDefaultHandling)
        #expect(credential == nil)
    }

    @Test("a server trust challenge is answered by the trust evaluator at session and task level")
    func serverTrustGoesToEvaluator() async {
        let (session, task) = makeSessionAndTask()
        defer { session.invalidateAndCancel() }
        let calls = LockIsolatedBox(0)
        let delegate = makeDelegate(store: ClientIdentityStore(keychain: .inMemory()), calls: calls)
        let challenge = ClientCertificateChallengeFixture.make(host: TestHost.server, port: 443, method: NSURLAuthenticationMethodServerTrust)

        let sessionAnswer = await delegate.urlSession(session, didReceive: challenge)
        let taskAnswer = await delegate.urlSession(session, task: task, didReceive: challenge)

        #expect(sessionAnswer.0 == .cancelAuthenticationChallenge)
        #expect(taskAnswer.0 == .cancelAuthenticationChallenge)
        #expect(calls.value == 2)
    }

    @Test("a client certificate challenge with an installed identity is answered with it and never reaches the trust evaluator")
    func clientCertificateIsAnsweredFirst() async throws {
        let store = ClientIdentityStore(keychain: .inMemory())
        let origin = ClientCertificateOrigin(host: TestHost.server, port: 443)
        try store.install(pkcs12: MutualTLSFixtures.data(.clientIdentity), passphrase: MutualTLSFixtures.passphrase, for: origin)
        let (session, task) = makeSessionAndTask()
        defer { session.invalidateAndCancel() }
        let calls = LockIsolatedBox(0)
        let delegate = makeDelegate(store: store, calls: calls)
        let challenge = ClientCertificateChallengeFixture.make(host: TestHost.server, port: 443)

        let sessionAnswer = await delegate.urlSession(session, didReceive: challenge)
        let taskAnswer = await delegate.urlSession(session, task: task, didReceive: challenge)

        #expect(sessionAnswer.0 == .useCredential)
        #expect(sessionAnswer.1 != nil)
        #expect(taskAnswer.0 == .useCredential)
        #expect(taskAnswer.1 != nil)
        #expect(calls.value == 0)
    }

    @Test("a client certificate challenge without an installed identity gets the default handling and no credential")
    func missingIdentityGetsDefaultHandling() async {
        let (session, task) = makeSessionAndTask()
        defer { session.invalidateAndCancel() }
        let calls = LockIsolatedBox(0)
        let delegate = makeDelegate(store: ClientIdentityStore(keychain: .inMemory()), calls: calls)
        let challenge = ClientCertificateChallengeFixture.make(host: TestHost.server, port: 443)

        let answer = await delegate.urlSession(session, didReceive: challenge)

        #expect(answer.0 == .performDefaultHandling)
        #expect(answer.1 == nil)
        #expect(calls.value == 0)
    }
}
