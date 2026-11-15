import Foundation

/// A cookie-free view of one signed-in account, published by `AppFeature` for the Settings
/// account switcher to render. Deliberately carries no session cookie or token: the switcher only
/// needs identity and which account is active, and secrets must not spread into the feature layer.
public struct AccountSummary: Codable, Equatable, Identifiable, Sendable {
    /// Matches `SessionCredentials.accountID` (server + username), so a switch/remove delegate can
    /// name one account back to `AppFeature`.
    public var id: String
    public var username: String
    public var serverURL: URL
    public var isActive: Bool

    public init(id: String, username: String, serverURL: URL, isActive: Bool) {
        self.id = id
        self.username = username
        self.serverURL = serverURL
        self.isActive = isActive
    }

    /// `@Shared(.inMemory(...))` key holding the current signed-in account list.
    public static let sharedKey = "signedInAccounts"

    public var serverHost: String {
        guard let host = serverURL.host else { return serverURL.absoluteString }
        // Keep an explicit port (e.g. a LAN instance at 192.168.1.187:3660), so it is
        // distinguishable from a tunnel/domain entry for the same server. Default ports aren't in
        // the URL, so `port` is nil for them and nothing is appended.
        if let port = serverURL.port {
            return "\(host):\(port)"
        }
        return host
    }

    /// A display name for the account when no richer profile is available: the username, or the
    /// server host as a last resort.
    public var displayName: String {
        username.isEmpty ? serverHost : username
    }
}
