import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    func favorites(serverURL: URL) async throws -> [Favorite] {
        let url = serverURL.appendingPathComponent(APIPath.favorites)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: [Favorite].self)
    }

    func addFavorite(serverURL: URL, path: String) async throws -> Favorite {
        let url = serverURL.appendingPathComponent(APIPath.favorites)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(FavoritePathBody(path: path))
        return try await send(request, decoding: Favorite.self)
    }

    /// `PATCH /api/favorites/:id`, confirmed against `backend/src/services/favoritesService.js`
    /// `updateFavorite`: `{ label, icon, color }` (position left to the reorder endpoint).
    func updateFavorite(serverURL: URL, id: String, label: String?, icon: String, color: String?) async throws -> Favorite {
        let url = serverURL.appendingPathComponent(APIPath.favorites).appendingPathComponent(id)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        request.httpBody = try Self.encode(UpdateFavoriteBody(label: label, icon: icon, color: color))
        return try await sendReportingMessage(request, decoding: Favorite.self)
    }

    /// `PATCH /api/favorites/reorder`: `{ order: [id, ...] }` — every id, once. Returns the
    /// full list in the new order.
    func reorderFavorites(serverURL: URL, orderedIDs: [String]) async throws -> [Favorite] {
        let url = serverURL.appendingPathComponent(APIPath.favoritesReorder)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ReorderFavoritesBody(order: orderedIDs))
        return try await sendReportingMessage(request, decoding: [Favorite].self)
    }

    func removeFavorite(serverURL: URL, path: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.favorites)
        var request = Self.makeRequest(url: url, method: .delete)
        request.setJSONContentType()
        request.httpBody = try Self.encode(FavoritePathBody(path: path))
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }
}
