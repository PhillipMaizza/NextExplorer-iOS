/// Mirrors `GET /api/auth/status` — which auth methods this NextExplorer server has
/// enabled. Confirmed nested shape: `{ strategies: { local, oidc }, ... }`.
public struct AuthStatus: Codable, Equatable, Sendable {
    public let localEnabled: Bool
    public let oidcEnabled: Bool

    public init(localEnabled: Bool, oidcEnabled: Bool) {
        self.localEnabled = localEnabled
        self.oidcEnabled = oidcEnabled
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
