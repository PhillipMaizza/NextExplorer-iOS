import Foundation

final class URLSessionAuthDelegate: NSObject, URLSessionTaskDelegate {
    private let trustEvaluator: ServerTrustEvaluating

    init(trustEvaluator: ServerTrustEvaluating) {
        self.trustEvaluator = trustEvaluator
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await trustEvaluator.evaluate(challenge)
    }
}
