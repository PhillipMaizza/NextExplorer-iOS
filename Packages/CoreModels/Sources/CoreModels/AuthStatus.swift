/// Mirrors `GET /api/auth/status`: which auth methods this NextExplorer server has
/// enabled. Confirmed nested shape: `{ strategies: { local, oidc }, ... }`.
public struct AuthStatus: Codable, Equatable, Sendable {
    public let localEnabled: Bool
    public let oidcEnabled: Bool
    /// The http address answered from https on the same host (a redirect). Signing in must then
    /// go to https directly: a redirected sign in loses its body, and the password would have
    /// crossed the network unencrypted first. Not part of the server's JSON.
    public var redirectsToHTTPS = false
    /// The port the https address answered on when it is not the default one, so the saved
    /// address matches where the server answered. `nil` is the default https port. Not part of the
    /// server's JSON.
    public var redirectedPort: Int?

    public init(localEnabled: Bool, oidcEnabled: Bool, redirectsToHTTPS: Bool = false, redirectedPort: Int? = nil) {
        self.localEnabled = localEnabled
        self.oidcEnabled = oidcEnabled
        self.redirectsToHTTPS = redirectsToHTTPS
        self.redirectedPort = redirectedPort
    }

    private enum CodingKeys: String, CodingKey {
        case strategies
    }

    private enum StrategiesCodingKeys: String, CodingKey {
        case local, oidc
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let strategies = try container.nestedContainer(keyedBy: StrategiesCodingKeys.self, forKey: .strategies)
        localEnabled = try strategies.decode(Bool.self, forKey: .local)
        oidcEnabled = try strategies.decode(Bool.self, forKey: .oidc)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var strategies = container.nestedContainer(keyedBy: StrategiesCodingKeys.self, forKey: .strategies)
        try strategies.encode(localEnabled, forKey: .local)
        try strategies.encode(oidcEnabled, forKey: .oidc)
    }
}
