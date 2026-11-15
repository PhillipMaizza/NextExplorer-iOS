import Foundation

/// Body for `POST /api/users` (admin). The server derives `username` and `displayName` from
/// the email when omitted. `isAdmin` maps to `roles: ["admin"]` or `roles: []`.
public struct CreateUserRequest: Equatable, Sendable {
    public var email: String
    public var username: String?
    public var password: String
    public var displayName: String?
    public var isAdmin: Bool

    public init(
        email: String,
        username: String? = nil,
        password: String,
        displayName: String? = nil,
        isAdmin: Bool = false
    ) {
        self.email = email
        self.username = username
        self.password = password
        self.displayName = displayName
        self.isAdmin = isAdmin
    }
}

/// Body for `PATCH /api/users/:id` (admin). Only the non nil fields are sent. `roles` and the
/// profile fields can be updated in the same call.
public struct UpdateUserRequest: Equatable, Sendable {
    public var email: String?
    public var username: String?
    public var displayName: String?
    public var roles: [String]?

    public init(email: String? = nil, username: String? = nil, displayName: String? = nil, roles: [String]? = nil) {
        self.email = email
        self.username = username
        self.displayName = displayName
        self.roles = roles
    }
}

/// Body for `POST /api/users/:id/volumes` (admin, `USER_VOLUMES` feature only).
public struct AddUserVolumeRequest: Equatable, Sendable {
    public var label: String
    public var path: String
    public var accessMode: ShareAccessMode

    public init(label: String, path: String, accessMode: ShareAccessMode = .readwrite) {
        self.label = label
        self.path = path
        self.accessMode = accessMode
    }
}
