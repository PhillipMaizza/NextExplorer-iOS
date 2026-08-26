import CoreModels
import Foundation
import NetworkClient

/// Plain JSON REST calls against NextExplorer's file-browsing endpoints
/// (`/api/browse`, `/api/search`, `/api/favorites`, `/api/volumes`). Auth is
/// implicit: the session cookie captured by `AuthClient` rides along on
/// every request via the shared `HTTPCookieStorage`.
struct FilesService: Sendable {
    let networkClient: NetworkClient

    func browse(serverURL: URL, path: String) async throws -> BrowseResult {
        let url = Self.browseURL(serverURL: serverURL, path: path)
        let request = Self.makeRequest(url: url, method: "GET")
        return try await send(request, decoding: BrowseResult.self)
    }

    func search(serverURL: URL, path: String, query: String, limit: Int?) async throws -> [SearchResultItem] {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/search"), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if !path.isEmpty {
            queryItems.append(URLQueryItem(name: "path", value: path))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw FilesClientError.decoding("Could not build search URL.")
        }
        let request = Self.makeRequest(url: url, method: "GET")
        let envelope = try await send(request, decoding: SearchEnvelope.self)
        return envelope.items
    }

    func favorites(serverURL: URL) async throws -> [Favorite] {
        let url = serverURL.appendingPathComponent("api/favorites")
        let request = Self.makeRequest(url: url, method: "GET")
        return try await send(request, decoding: [Favorite].self)
    }

    func addFavorite(serverURL: URL, path: String) async throws -> Favorite {
        let url = serverURL.appendingPathComponent("api/favorites")
        var request = Self.makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(FavoritePathBody(path: path))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await send(request, decoding: Favorite.self)
    }

    func removeFavorite(serverURL: URL, path: String) async throws {
        let url = serverURL.appendingPathComponent("api/favorites")
        var request = Self.makeRequest(url: url, method: "DELETE")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(FavoritePathBody(path: path))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// `POST /api/files/rename`, confirmed against `backend/src/routes/files/rename.js`:
    /// `path` is the item's *parent* directory, `name` its current name — matching `FileItem`'s
    /// own `path`/`name` fields exactly, so the whole item can be forwarded unchanged.
    func renameItem(serverURL: URL, item: FileItem, newName: String) async throws -> FileItem {
        let url = serverURL.appendingPathComponent("api/files/rename")
        var request = Self.makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(RenameItemBody(path: item.path, name: item.name, newName: newName))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: RenameItemEnvelope.self)
        return envelope.item
    }

    /// `GET /api/metadata/*`, confirmed against `backend/src/routes/metadata.js`: a single
    /// wildcard path segment covering the item's full logical path (parent + name), same
    /// percent-encoding-per-segment approach as `browseURL`.
    func fetchMetadata(serverURL: URL, path: String) async throws -> FileMetadata {
        var url = serverURL.appendingPathComponent("api/metadata")
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        for segment in segments {
            url = url.appendingPathComponent(String(segment))
        }
        let request = Self.makeRequest(url: url, method: "GET")
        return try await send(request, decoding: FileMetadata.self)
    }

    /// `DELETE /api/files`, confirmed against `backend/src/routes/files/delete.js` and
    /// `fileTransferService.resolveDeleteTargets`: each item is `{path, name}` — again exactly
    /// `FileItem`'s own fields, `kind` included as the server's fallback for already-missing items.
    func deleteItems(serverURL: URL, items: [FileItem]) async throws {
        let url = serverURL.appendingPathComponent("api/files")
        var request = Self.makeRequest(url: url, method: "DELETE")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let body = DeleteItemsBody(items: items.map { DeleteItemsBody.Item(path: $0.path, name: $0.name, kind: $0.kind) })
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    func volumes(serverURL: URL) async throws -> [Volume] {
        let url = serverURL.appendingPathComponent("api/volumes")
        let request = Self.makeRequest(url: url, method: "GET")
        return try await send(request, decoding: [Volume].self)
    }

    func fetchPreferences(serverURL: URL) async throws -> UserPreferences {
        let url = serverURL.appendingPathComponent("api/settings")
        let request = Self.makeRequest(url: url, method: "GET")
        let envelope = try await send(request, decoding: SettingsEnvelope.self)
        return envelope.user ?? UserPreferences()
    }

    func updatePreference(serverURL: URL, key: UserPreferenceKey, value: Bool) async throws {
        let url = serverURL.appendingPathComponent("api/settings")
        var request = Self.makeRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(PatchPreferencesBody(user: [key.rawValue: value]))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    private struct SearchEnvelope: Decodable {
        let items: [SearchResultItem]
    }

    /// Only the `user` object of `GET /api/settings`'s response is decoded; `branding`
    /// and (admin-only) `thumbnails`/`access` aren't modeled by this client.
    private struct SettingsEnvelope: Decodable {
        let user: UserPreferences?
    }

    private struct PatchPreferencesBody: Encodable {
        let user: [String: Bool]
    }

    private struct FavoritePathBody: Encodable {
        let path: String
    }

    private struct RenameItemBody: Encodable {
        let path: String
        let name: String
        let newName: String
    }

    private struct RenameItemEnvelope: Decodable {
        let item: FileItem
    }

    private struct DeleteItemsBody: Encodable {
        struct Item: Encodable {
            let path: String
            let name: String
            let kind: String
        }

        let items: [Item]
    }

    /// `GET /api/browse/*`. An empty path browses the root and must still end in a
    /// trailing slash (`/api/browse/`); non-empty paths are split and each segment
    /// percent-encoded individually so names containing `/`-unsafe characters survive.
    private static func browseURL(serverURL: URL, path: String) -> URL {
        var url = serverURL.appendingPathComponent("api/browse")
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        if segments.isEmpty {
            return url.appendingPathComponent("")
        }
        for segment in segments {
            url = url.appendingPathComponent(String(segment))
        }
        return url
    }

    private func send<Response: Decodable>(_ request: URLRequest, decoding type: Response.Type) async throws -> Response {
        let (data, response) = try await performSend(request)
        try Self.validate(response)
        do {
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    private func performSend(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await networkClient.send(request)
        } catch {
            throw FilesClientError.network(String(describing: error))
        }
    }

    private static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw FilesClientError.sessionExpired
        case 429:
            throw FilesClientError.rateLimited
        default:
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    private static func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// `dateModified`/`createdAt`/`updatedAt` cross the wire as `Date.toISOString()`
    /// output (millisecond fractional seconds); the default `.iso8601` strategy's
    /// formatter rejects the fractional part, so fractional seconds must be opted in.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { keyedDecoder in
            let container = try keyedDecoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: dateString) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(dateString)")
            }
            return date
        }
        return decoder
    }
}
