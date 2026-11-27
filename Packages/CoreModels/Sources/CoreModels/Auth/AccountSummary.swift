import Foundation

/// A cookie free view of one signed in account, published by `AppFeature` for the Settings
/// account switcher to render. Deliberately carries no session cookie or token: the switcher only
/// needs identity and which account is active, and secrets must not spread into the feature layer.
public struct AccountSummary: Codable, Equatable, Identifiable, Sendable {
    /// Matches `SessionCredentials.accountID` (server + username), so a switch/remove delegate can
    /// name one account back to `AppFeature`.
    public var id: String
    public var username: String
    public var serverURL: URL
    public var isActive: Bool
    public var email: String?
    public var fullName: String?
    public var authMode: AuthMode
    public var requireSignIn: RequireSignIn?
    public var isLocked: Bool

    public init(
        id: String,
        username: String,
        serverURL: URL,
        isActive: Bool,
        email: String? = nil,
        fullName: String? = nil,
        authMode: AuthMode = .local,
        requireSignIn: RequireSignIn? = nil,
        isLocked: Bool = false
    ) {
        self.id = id
        self.username = username
        self.serverURL = serverURL
        self.isActive = isActive
        self.email = email
        self.fullName = fullName
        self.authMode = authMode
        self.requireSignIn = requireSignIn
        self.isLocked = isLocked
    }

    public init(_ credentials: SessionCredentials, isActive: Bool) {
        self.init(
            id: credentials.accountID,
            username: credentials.username ?? "",
            serverURL: credentials.serverBaseURL,
            isActive: isActive,
            email: credentials.email,
            fullName: credentials.displayName,
            authMode: credentials.authMode,
            requireSignIn: credentials.requireSignIn,
            isLocked: credentials.isLocked
        )
    }

    /// `@Shared(.inMemory(...))` key holding the current signed in account list.
    public static let sharedKey = "signedInAccounts"

    public var serverHost: String {
        serverURL.serverHost
    }

    /// The name the account is shown by, as the web names it: the display name, else the username,
    /// else the email (a single sign on user can have no username), else the server host.
    public var displayName: String {
        Self.name(fullName: fullName, username: username, email: email) ?? serverHost
    }

    /// The first non blank of the display name, username and email, wherever an account is named.
    public static func name(fullName: String? = nil, username: String?, email: String?) -> String? {
        [fullName, username, email].compactMap(\.self).first { !$0.isEmpty }
    }

    /// The server line under the name, left out when the name already is the server.
    public var serverSubtitle: String? {
        displayName == serverHost ? nil : serverHost
    }
}

public extension URL {
    /// The server's address as a person reads it: the host, plus the port when one is explicit.
    var serverHost: String {
        guard let host else { return absoluteString }
        // Keep an explicit port (e.g. a LAN instance at 192.168.1.187:3660), so it is
        // distinguishable from a tunnel/domain entry for the same server. Default ports aren't in
        // the URL, so `port` is nil for them and nothing is appended.
        if let port {
            return "\(host):\(port)"
        }
        return host
    }
}
