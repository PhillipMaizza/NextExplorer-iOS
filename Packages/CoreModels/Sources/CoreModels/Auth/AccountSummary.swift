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

    public init(id: String, username: String, serverURL: URL, isActive: Bool, email: String? = nil) {
        self.id = id
        self.username = username
        self.serverURL = serverURL
        self.isActive = isActive
        self.email = email
    }

    /// `@Shared(.inMemory(...))` key holding the current signed in account list.
    public static let sharedKey = "signedInAccounts"

    public var serverHost: String {
        serverURL.serverHost
    }

    /// The name the account is shown by: the username, else the email (a single sign on user can
    /// have no username), else the server host as a last resort.
    public var displayName: String {
        Self.name(username: username, email: email) ?? serverHost
    }

    /// The username, else the email, for any place that names an account; `nil` when both are blank.
    public static func name(username: String?, email: String?) -> String? {
        [username, email].compactMap(\.self).first { !$0.isEmpty }
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
