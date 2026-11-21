import Foundation

/// The OIDC mobile bridge's wire names, and the reading of the URL it redirects back to. The
/// callback arrives from a browser session, so it is untrusted input.
enum OIDCCallback {
    enum QueryKey {
        static let codeChallenge = "code_challenge"
        static let codeChallengeMethod = "code_challenge_method"
        static let code = "code"
        static let error = "error"
    }

    static let challengeMethod = "S256"

    /// The authorization code the callback carries, or the server's error.
    static func code(from callbackURL: URL) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let serverError = items.first(where: { $0.name == QueryKey.error })?.value {
            throw AuthClientError.oidcFailed(serverError)
        }
        guard let code = items.first(where: { $0.name == QueryKey.code })?.value, !code.isEmpty else {
            throw AuthClientError.oidcFailed("callback missing code")
        }
        return code
    }
}
