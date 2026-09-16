import Foundation

public protocol ServerTrustEvaluating: Sendable {
    func evaluate(_ challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?)
}

/// Defers to standard system trust evaluation — self-signed/internal-CA certs fail exactly
/// as they should today. The seam a later "trust this certificate" TOFU flow plugs into
/// without touching anything else in this package.
public struct DefaultServerTrustEvaluator: ServerTrustEvaluating {
    public init() {}

    public func evaluate(_: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.performDefaultHandling, nil)
    }
}
