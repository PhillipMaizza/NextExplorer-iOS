public enum AuthClientError: Error, Equatable, Sendable {
    case invalidCredentials
    case sessionExpired
    case sessionCookieMissing
    case network(String)
    case decoding(String)
    case keychain(String)
    case server(statusCode: Int)
    case noAuthMethodsEnabled
    /// The user dismissed the OIDC web sheet before finishing. A cancellation, not a failure:
    /// the UI clears its in-flight state silently rather than showing an error.
    case oidcCancelled
    /// The OIDC bridge flow failed (the web session errored, the callback carried an
    /// `error`, or the exchange could not complete). Carries a short reason for logging.
    case oidcFailed(String)
    /// 429 from the login route — covers both the login-attempt rate limiter and an
    /// account lockout (the server converts a 423 lockout into a 429 RateLimitError
    /// before it ever reaches the client; confirmed against `backend/src/routes/auth.js`).
    case rateLimited
}
