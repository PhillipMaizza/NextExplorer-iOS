import Foundation

final class URLSessionAuthDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let trustEvaluator: ServerTrustEvaluating

    init(trustEvaluator: ServerTrustEvaluating) {
        self.trustEvaluator = trustEvaluator
    }

    /// Session level handler. Connection level challenges (server trust) are delivered here for
    /// any task that carries its own delegate, such as the upload task and its
    /// `UploadProgressDelegate`, whose per task delegate has no challenge method of its own.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await trustEvaluator.evaluate(challenge)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await trustEvaluator.evaluate(challenge)
    }
}
