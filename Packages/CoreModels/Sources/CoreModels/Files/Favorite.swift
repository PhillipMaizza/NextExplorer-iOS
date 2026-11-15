import Foundation

/// Mirrors a row returned by `GET /api/favorites`, confirmed against
/// `backend/src/services/favoritesService.js`'s `mapDbFavorite`.
public struct Favorite: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let label: String?
    public let icon: String
    public let color: String?
    public let position: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        path: String,
        label: String?,
        icon: String,
        color: String?,
        position: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.path = path
        self.label = label
        self.icon = icon
        self.color = color
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Falls back to the last path component when the user hasn't set a custom label.
    public var displayName: String {
        label ?? path.split(separator: "/").last.map(String.init) ?? path
    }
}
