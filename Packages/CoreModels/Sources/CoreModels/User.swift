import Foundation

/// Mirrors the user object returned (wrapped under a `"user"` key) by
/// `POST /api/auth/login` and `GET /api/auth/me` — confirmed against
/// `backend/src/services/users/utils.js`'s `toClientUser`.
public struct User: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let username: String
    public let email: String?
    public let displayName: String?
    public let roles: [String]

    public var isAdmin: Bool { roles.contains("admin") }

    public init(id: String, username: String, email: String?, displayName: String? = nil, roles: [String] = []) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.roles = roles
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, email, displayName, roles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeIDAsString(container, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(roles, forKey: .roles)
    }

    /// The server's `id` type isn't confirmed (DB auto-increment integer vs. string) —
    /// accept either rather than fail decoding over it.
    private static func decodeIDAsString(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> String {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return stringValue
        }
        let intValue = try container.decode(Int.self, forKey: key)
        return String(intValue)
    }
}
