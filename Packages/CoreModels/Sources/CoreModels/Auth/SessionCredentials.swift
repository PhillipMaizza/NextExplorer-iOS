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
    public var isCookieSecure: Bool
    /// `nil` when the server issued a session-scoped cookie with no explicit Expires/Max-Age:
    /// liveness is then determined solely by calling `/api/auth/me`, never by local clock math.
    public var expiresAt: Date?
    public var username: String?
    /// Shown for the account when the server has no username for it, as with some single sign on users.
    public var email: String?

    /// The Keychain blob keeps the names earlier releases wrote, so stored sessions still read.
    private enum CodingKeys: String, CodingKey {
        case serverBaseURL, authMode, cookieName, cookieValue, cookieDomain, cookiePath, expiresAt, username, email
        case isCookieSecure = "cookieIsSecure"
    }

    public init(
        serverBaseURL: URL,
        authMode: AuthMode,
        cookieName: String,
        cookieValue: String,
        cookieDomain: String,
        cookiePath: String,
        isCookieSecure: Bool,
        expiresAt: Date?,
        username: String?,
        email: String? = nil
    ) {
        self.serverBaseURL = serverBaseURL
        self.authMode = authMode
        self.cookieName = cookieName
        self.cookieValue = cookieValue
        self.cookieDomain = cookieDomain
        self.cookiePath = cookiePath
        self.isCookieSecure = isCookieSecure
        self.expiresAt = expiresAt
        self.username = username
        self.email = email
    }

    /// Stable identity of the account this session belongs to, so the multi-server switcher can
    /// list, activate and remove one specific account. Keyed on the server plus the username, so
    /// two accounts on the same server are still distinct. Not persisted: derived, so it survives
    /// an older stored blob that predates it.
    public var accountID: String {
        serverBaseURL.absoluteString + "|" + (username ?? "")
    }

    /// The `Cookie` header value that speaks for this account alone, for a request that must not
    /// carry whichever account's cookie the shared jar holds.
    public var cookieHeader: String {
        "\(cookieName)=\(cookieValue)"
    }

    /// Reconstructs the `HTTPCookie` this session was captured from, so it can be
    /// reinstalled into `HTTPCookieStorage.appSession` on app relaunch. It is always session only:
    /// a cookie with an expiry is written to `Library/Cookies`, and the token belongs in the Keychain
    /// alone. `expiresAt` stays on the credentials for the app's own expiry handling.
    public var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: cookieName,
            .value: cookieValue,
            .domain: cookieDomain,
            .path: cookiePath,
        ]
        // `HTTPCookiePropertyKey.secure`'s mere PRESENCE marks the cookie secure, regardless
        // of its string value: it must be omitted entirely to produce a non-secure cookie.
        if isCookieSecure {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }
}
