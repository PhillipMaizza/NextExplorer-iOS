import Foundation

/// The Keychain-persisted shape of an authenticated session: everything needed to
/// reinstall the server's session cookie into `HTTPCookieStorage` on relaunch.
public struct SessionCredentials: Codable, Equatable, Sendable {
    public var serverBaseURL: URL
    public var authMode: AuthMode
    public var cookieName: String
    public var cookieValue: String
    public var cookieDomain: String
    public var cookiePath: String
    public var cookieIsSecure: Bool
    /// `nil` when the server issued a session-scoped cookie with no explicit Expires/Max-Age —
    /// liveness is then determined solely by calling `/api/auth/me`, never by local clock math.
    public var expiresAt: Date?
    public var username: String?

    public init(
        serverBaseURL: URL,
        authMode: AuthMode,
        cookieName: String,
        cookieValue: String,
        cookieDomain: String,
        cookiePath: String,
        cookieIsSecure: Bool,
        expiresAt: Date?,
        username: String?
    ) {
        self.serverBaseURL = serverBaseURL
        self.authMode = authMode
        self.cookieName = cookieName
        self.cookieValue = cookieValue
        self.cookieDomain = cookieDomain
        self.cookiePath = cookiePath
        self.cookieIsSecure = cookieIsSecure
        self.expiresAt = expiresAt
        self.username = username
    }

    /// Reconstructs the `HTTPCookie` this session was captured from, so it can be
    /// reinstalled into `HTTPCookieStorage.shared` on app relaunch.
    public var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: cookieName,
            .value: cookieValue,
            .domain: cookieDomain,
            .path: cookiePath,
        ]
        // `HTTPCookiePropertyKey.secure`'s mere PRESENCE marks the cookie secure, regardless
        // of its string value — it must be omitted entirely to produce a non-secure cookie.
        if cookieIsSecure {
            properties[.secure] = "TRUE"
        }
        if let expiresAt {
            properties[.expires] = expiresAt
        }
        return HTTPCookie(properties: properties)
    }
}
