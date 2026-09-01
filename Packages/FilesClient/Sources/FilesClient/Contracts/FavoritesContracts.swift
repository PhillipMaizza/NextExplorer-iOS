import CoreModels
import Foundation

/// Wire types for the Favorites endpoints. See `FilesService+Favorites.swift`.
extension FilesService {
    struct FavoritePathBody: Encodable {
        let path: String
    }

    /// All three keys are always written — `null` included — so the server (which skips
    /// `undefined` keys) actually clears a removed label or colour rather than keeping the old one.
    struct UpdateFavoriteBody: Encodable {
        let label: String?
        let icon: String
        let color: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            try container.encode(icon, forKey: .icon)
            try container.encode(color, forKey: .color)
        }

        enum CodingKeys: String, CodingKey { case label, icon, color }
    }

    struct ReorderFavoritesBody: Encodable {
        let order: [String]
    }
}
