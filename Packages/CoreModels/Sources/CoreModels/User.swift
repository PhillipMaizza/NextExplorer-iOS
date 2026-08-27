import Foundation

/// Mirrors the user object returned (wrapped under a `"user"` key) by
/// `POST /api/auth/login` and `GET /api/auth/me` — confirmed against
/// `backend/src/services/users/utils.js`'s `toClientUser`.
public struct User: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let username: String
    public let email: String?
    public let displayName: String?
    public let roles: [String]
    public let emailVerified: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
    /// Only populated by the admin `GET /api/users` list — empty for `/api/auth/me`.
    public let authMethods: [AuthMethod]

    public var isAdmin: Bool { roles.contains("admin") }
    /// Whether this user can sign in with a local email/password (vs. SSO only).
    public var hasLocalPassword: Bool { authMethods.contains { $0.isPassword } }
    public var oidcMethods: [AuthMethod] { authMethods.filter { $0.isOIDC } }

    public init(
        id: String,
        username: String,
        email: String?,
        displayName: String? = nil,
        roles: [String] = [],
        emailVerified: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        authMethods: [AuthMethod] = []
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.roles = roles
        self.emailVerified = emailVerified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.authMethods = authMethods
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, email, displayName, roles, emailVerified, createdAt, updatedAt, authMethods
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeIDAsString(container, forKey: .id)
        // The server column is nullable, and the admin "edit user" form can blank it out
        // (`values.push(trimmed || null)`), so a later `/api/users` response could carry
        // `username: null` — that must not fail the decode of the whole list.
        username = (try? container.decodeIfPresent(String.self, forKey: .username)) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []
        emailVerified = (try? container.decodeIfPresent(Bool.self, forKey: .emailVerified)) ?? false
        createdAt = Self.decodeTimestamp(container, forKey: .createdAt)
        updatedAt = Self.decodeTimestamp(container, forKey: .updatedAt)
        authMethods = (try? container.decodeIfPresent([AuthMethod].self, forKey: .authMethods)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(roles, forKey: .roles)
        try container.encode(emailVerified, forKey: .emailVerified)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(authMethods, forKey: .authMethods)
    }

    /// `createdAt` / `updatedAt` are metadata the admin user list shows and nothing else
    /// depends on — a missing, non-ISO, or type-mismatched timestamp must never fail a
    /// `User` decode (the login and `/api/auth/me` responses go through a plain `JSONDecoder`
    /// with no date strategy, so a date *string* there would otherwise throw). Tolerate every
    /// shape; give up to `nil` rather than propagate.
    private static func decodeTimestamp(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: raw) ?? plain.date(from: raw)
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
