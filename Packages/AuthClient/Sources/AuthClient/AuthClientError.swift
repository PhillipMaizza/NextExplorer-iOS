public enum AuthClientError: Error, Equatable, Sendable {
    case invalidCredentials
    case sessionExpired
    case sessionCookieMissing
    case network(String)
    case decoding(String)
    case keychain(String)
    case server(statusCode: Int)
    case noAuthMethodsEnabled
    /// 429 from the login route — covers both the login-attempt rate limiter and an
    /// account lockout (the server converts a 423 lockout into a 429 RateLimitError
    /// before it ever reaches the client; confirmed against `backend/src/routes/auth.js`).
    case rateLimited
}
