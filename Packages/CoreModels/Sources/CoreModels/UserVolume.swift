import Foundation

/// A directory assigned to a specific user when the server's `USER_VOLUMES` feature is on.
/// Mirrors `backend/src/services/userVolumesService.js`'s `toClientVolume`.
public struct UserVolume: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let label: String
    public let path: String
    public let accessMode: ShareAccessMode
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        userId: String,
        label: String,
        path: String,
        accessMode: ShareAccessMode,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.label = label
        self.path = path
        self.accessMode = accessMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One directory in the admin directory browser (`GET /api/admin/browse-directories`),
/// used when assigning a volume to a user.
public struct AdminDirectory: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let path: String

    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// A page of the admin directory browser: the directory being listed, its parent (nil at the
/// volume root), and the child directories.
public struct AdminDirectoryListing: Codable, Equatable, Sendable {
    public let current: String
    public let parent: String?
    public let directories: [AdminDirectory]

    public init(current: String, parent: String?, directories: [AdminDirectory]) {
        self.current = current
        self.parent = parent
        self.directories = directories
    }
}
