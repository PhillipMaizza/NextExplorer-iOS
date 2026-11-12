import Foundation

enum ClientCertificateChallengeFixture {
    private final class Sender: NSObject, URLAuthenticationChallengeSender {
        func use(_: URLCredential, for _: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for _: URLAuthenticationChallenge) {}
        func cancel(_: URLAuthenticationChallenge) {}
    }

    static func make(
        host: String,
        port: Int,
        method: String = NSURLAuthenticationMethodClientCertificate
    ) -> URLAuthenticationChallenge {
        let space = URLProtectionSpace(host: host, port: port, protocol: "https", realm: nil, authenticationMethod: method)
        return URLAuthenticationChallenge(
            protectionSpace: space,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: Sender()
        )
    }
}
