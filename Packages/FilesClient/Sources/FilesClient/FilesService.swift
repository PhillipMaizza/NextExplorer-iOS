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

    /// `GET /api/thumbnails/*`, confirmed against `backend/src/routes/thumbnails.js`: returns
    /// `{ thumbnail: "" }` when thumbnails are disabled server-side or the file's type isn't
    /// thumbnailable, `{ thumbnail: "/static/thumbnails/<hash>.webp" }` once generated (cached
    /// after the first request), or `{ thumbnail: "/api/preview?path=..." }` as a fallback for
    /// images whose thumbnail generation failed. All three are server-relative, resolved
    /// against `serverURL`; an empty string means "no thumbnail," not an error.
    func thumbnailURL(serverURL: URL, path: String) async throws -> URL? {
        var url = serverURL.appendingPathComponent("api/thumbnails")
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        for segment in segments {
            url = url.appendingPathComponent(String(segment))
        }
        let request = Self.makeRequest(url: url, method: "GET")
        let envelope = try await send(request, decoding: ThumbnailEnvelope.self)
        guard !envelope.thumbnail.isEmpty else { return nil }
        return URL(string: envelope.thumbnail, relativeTo: serverURL)?.absoluteURL
    }

    /// `GET /api/preview?path=...`, confirmed against `backend/src/routes/files/preview.js`:
    /// streams the raw file with the correct `Content-Type`. Downloaded whole into memory and
    /// written to a fresh temp subdirectory (not a shared/reused path — two different files
    /// with the same name would otherwise collide) so `QLPreviewController` gets a local file
    /// URL with the right extension for UTI detection.
    /// Cached on disk (`Library/Caches`, survives across launches, purged only under storage
    /// pressure) keyed by the item's own path — not a fresh directory per call — so reopening
    /// the same unchanged file never re-hits the server. Staleness is checked via a small
    /// sidecar recording `dateModified`/`size` at download time: if either differs from the
    /// current `item`, the cache is treated as stale and re-downloaded.
    /// `POST /api/editor` / `PUT /api/editor`, confirmed against `backend/src/routes/editor.js`:
    /// the real text view/edit path for anything `GET /api/preview` won't serve (415s on
    /// everything outside images/RAW/video/audio/pdf) — plain text, markdown, code, config
    /// files. The server itself enforces a size cap (1MB default) and sniffs for binary
    /// content, surfacing either as a plain validation error this maps to `.server(statusCode:)`.
    func fetchTextContent(serverURL: URL, path: String) async throws -> String {
        let url = serverURL.appendingPathComponent("api/editor")
        var request = Self.makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(EditorPathBody(path: path))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: EditorContentEnvelope.self)
        return envelope.content
    }

    func saveTextContent(serverURL: URL, path: String, content: String) async throws {
        let url = serverURL.appendingPathComponent("api/editor")
        var request = Self.makeRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(EditorSaveBody(path: path, content: content))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// `POST /api/files/zip/extract`, confirmed against `backend/src/routes/zip.js`: unpacks
    /// the archive into a *new* sibling folder (named after the zip, deduped if taken) and
    /// returns that folder as an item — there's no listing-only/peek-inside endpoint, and only
    /// `.zip` is supported server-side (`.rar`/`.7z`/etc. 415 with "Only .zip archives...").
    func extractZip(serverURL: URL, item: FileItem) async throws -> FileItem {
        let url = serverURL.appendingPathComponent("api/files/zip/extract")
        var request = Self.makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(ExtractZipBody(path: item.id))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: ExtractZipEnvelope.self)
        return envelope.item
    }

    /// `POST /api/files/zip/compress`, confirmed against `backend/src/routes/zip.js`: zips a
    /// single item (file or directory) into a new sibling archive in its own parent folder,
    /// auto-naming it from the source (`defaultZipNameForItems`) when `name` is omitted.
    func compressItem(serverURL: URL, item: FileItem) async throws -> FileItem {
        let url = serverURL.appendingPathComponent("api/files/zip/compress")
        var request = Self.makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let body = CompressItemBody(items: [CompressItemBody.Item(name: item.name, path: item.path)], destination: item.path)
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: CompressItemEnvelope.self)
        return envelope.item
    }

    func previewFile(serverURL: URL, item: FileItem) async throws -> URL {
        let directory = Self.previewCacheDirectory(for: item, namespace: "preview")
        // RAW formats always come back as a JPEG stream (`rawPreviewService`), regardless of
        // the original extension — save with a matching extension or QuickLook's UTI
        // detection (extension-based) tries to render JPEG bytes as e.g. `.nef` and fails.
        let fileName = item.isRawImage ? "\(item.name).jpg" : item.name
        let fileURL = directory.appendingPathComponent(fileName)
        let metaURL = directory.appendingPathComponent(".meta")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let cachedMeta = try? String(contentsOf: metaURL, encoding: .utf8),
           cachedMeta == Self.cacheMetaValue(for: item) {
            return fileURL
        }

        guard let url = FilesClient.previewURL(serverURL: serverURL, item: item) else {
            throw FilesClientError.decoding("Could not build preview URL.")
        }
        let request = Self.makeRequest(url: url, method: "GET")
        let (data, response) = try await performSend(request)
        try Self.validate(response)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try Self.cacheMetaValue(for: item).write(to: metaURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// `POST /api/download`, confirmed against `backend/src/routes/files/download.js` mounted
    /// at plain `/api` (not `/api/files`) in `backend/src/routes/index.js` — easy to get wrong
    /// by pattern-matching the file's own path (`routes/files/download.js`) instead of its
    /// actual mount point.
    /// unlike `GET /api/preview`, this isn't restricted to `PREVIEWABLE_EXTENSIONS` — a single
    /// non-directory target streams back as the raw file (`res.download`), whatever its kind.
    /// That's what makes client-side archive browsing (`ZIPFoundation`/`Unrar.swift`) possible
    /// at all: the server has no listing-only endpoint, so the whole archive has to come down
    /// first. Reuses `previewFile`'s cache layout (same staleness key) but under its own
    /// `namespace`, so the two endpoints never share a cache slot for the same item.
    func downloadRawFile(serverURL: URL, item: FileItem) async throws -> URL {
        let directory = Self.previewCacheDirectory(for: item, namespace: "download")
        let fileURL = directory.appendingPathComponent(item.name)
        let metaURL = directory.appendingPathComponent(".meta")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let cachedMeta = try? String(contentsOf: metaURL, encoding: .utf8),
           cachedMeta == Self.cacheMetaValue(for: item) {
            return fileURL
        }

        let url = serverURL.appendingPathComponent("api/download")
        var request = Self.makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(DownloadRawFileBody(path: item.id))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (data, response) = try await performSend(request)
        try Self.validate(response)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try Self.cacheMetaValue(for: item).write(to: metaURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// One subdirectory per item path (slashes swapped out so it's a single valid path
    /// component) — distinct files that happen to share a name never collide, since they
    /// have distinct full paths. `namespace` keeps `previewFile` (`GET /api/preview`) and
    /// `downloadRawFile` (`POST /api/download`) from ever sharing a cache entry for the same
    /// item — two different endpoints, nothing guarantees they'll always serve identical bytes
    /// for every kind that happens to use both (RAW images already diverge one direction).
    private static func previewCacheDirectory(for item: FileItem, namespace: String) -> URL {
        let cachesDirectory = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let key = item.id.replacingOccurrences(of: "/", with: "_")
        return cachesDirectory.appendingPathComponent("PreviewCache", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }

    private static func cacheMetaValue(for item: FileItem) -> String {
        "\(item.dateModified.timeIntervalSince1970)|\(item.size)"
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

    private struct ThumbnailEnvelope: Decodable {
        let thumbnail: String
    }

    private struct EditorPathBody: Encodable {
        let path: String
    }

    private struct EditorContentEnvelope: Decodable {
        let content: String
    }

    private struct EditorSaveBody: Encodable {
        let path: String
        let content: String
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

    private struct ExtractZipBody: Encodable {
        let path: String
    }

    private struct ExtractZipEnvelope: Decodable {
        let item: FileItem
    }

    private struct CompressItemBody: Encodable {
        struct Item: Encodable {
            let name: String
            let path: String
        }
        let items: [Item]
        let destination: String
    }

    private struct CompressItemEnvelope: Decodable {
        let item: FileItem
    }

    private struct DownloadRawFileBody: Encodable {
        let path: String
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
