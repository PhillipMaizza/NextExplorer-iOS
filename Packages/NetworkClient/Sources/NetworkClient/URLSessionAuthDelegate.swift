import Foundation

/// `@unchecked Sendable`: holds only immutable `let`s (each `Sendable`) and the two
/// challenge handlers just forward to them, so it is safe to share across sessions: the live
/// `NetworkClient` gives the interactive and the low-priority `URLSession` the same instance,
/// and each delivers callbacks on its own queue.
final class URLSessionAuthDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let trustEvaluator: ServerTrustEvaluating
    private let certificates: ClientCertificateChallengeHandler

    init(trustEvaluator: ServerTrustEvaluating, certificates: ClientCertificateChallengeHandler) {
        self.trustEvaluator = trustEvaluator
        self.certificates = certificates
    }

    /// Session level handler. Connection level challenges (server trust) are delivered here for
    /// any task that carries its own delegate, such as the upload task and its
    /// `UploadProgressDelegate`, whose per task delegate has no challenge method of its own.
    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await respond(to: challenge)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await respond(to: challenge)
    }

    private func respond(to challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let answer = certificates.handle(challenge) {
            return answer
        }
        return await trustEvaluator.evaluate(challenge)
    }
}
