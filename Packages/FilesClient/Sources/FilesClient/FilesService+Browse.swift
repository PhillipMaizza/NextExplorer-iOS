import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    /// A conditional `GET /api/browse/*`. `ifNoneMatch` is the `ETag` from a previously cached
    /// listing; the server answers `304` (`.notModified`) when the directory is unchanged,
    /// sparing the transfer and the decode. `lowPriority` routes the request through the
    /// capped background session for prefetch. `.reloadIgnoringLocalCacheData` keeps
    /// URLSession's own cache out of the way so the app's cache stays authoritative.
    func browse(
        serverURL: URL, path: String, ifNoneMatch: String?, lowPriority: Bool = false
    ) async throws -> BrowseFetchOutcome {
        let url = Self.browseURL(serverURL: serverURL, path: path)
        var request = Self.makeRequest(url: url, method: .get)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let ifNoneMatch, !ifNoneMatch.isEmpty {
            request.setValue(ifNoneMatch, forHTTPHeaderField: HTTPHeaderField.ifNoneMatch)
        }

        let (data, response) = try await performSend(request, lowPriority: lowPriority)
        let etag = response.value(forHTTPHeaderField: HTTPHeaderField.etag)

        if response.statusCode == 304 {
            return .notModified(etag: etag)
        }
        try Self.validate(response)
        do {
            let result = try Self.makeDecoder().decode(BrowseResult.self, from: data)
            return .modified(result, etag: etag)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    func search(serverURL: URL, path: String, query: String, limit: Int?) async throws -> [SearchResultItem] {
        var components = URLComponents(url: serverURL.appendingPathComponent(APIPath.search), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: QueryKey.query, value: query)]
        if !path.isEmpty {
            queryItems.append(URLQueryItem(name: QueryKey.path, value: path))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: QueryKey.limit, value: String(limit)))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw FilesClientError.decoding("Could not build search URL.")
        }
        let request = Self.makeRequest(url: url, method: .get)
        let envelope = try await send(request, decoding: SearchEnvelope.self)
        return envelope.items
    }

    /// `GET /api/thumbnails/*`, confirmed against `backend/src/routes/thumbnails.js`: returns
    /// `{ thumbnail: "" }` when thumbnails are disabled server-side or the file's type isn't
    /// thumbnailable, `{ thumbnail: "/static/thumbnails/<hash>.webp" }` once generated (cached
    /// after the first request), or `{ thumbnail: "/api/preview?path=..." }` as a fallback for
    /// images whose thumbnail generation failed. All three are server-relative, resolved
    /// against `serverURL`; an empty string means "no thumbnail," not an error.
    func thumbnailURL(serverURL: URL, path: String) async throws -> URL? {
        let url = Self.appendingPathSegments(of: path, to: serverURL.appendingPathComponent(APIPath.thumbnails))
        let request = Self.makeRequest(url: url, method: .get)
        let envelope = try await send(request, decoding: ThumbnailEnvelope.self)
        guard !envelope.thumbnail.isEmpty else { return nil }
        return URL(string: envelope.thumbnail, relativeTo: serverURL)?.absoluteURL
    }

    /// `GET /api/metadata/*`, confirmed against `backend/src/routes/metadata.js`: a single
    /// wildcard path segment covering the item's full logical path (parent + name), same
    /// percent-encoding-per-segment approach as `browseURL`.
    func fetchMetadata(serverURL: URL, path: String) async throws -> FileMetadata {
        let url = Self.appendingPathSegments(of: path, to: serverURL.appendingPathComponent(APIPath.metadata))
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: FileMetadata.self)
    }

    /// `GET /api/usage/*`, confirmed against `backend/src/routes/usage.js`: one wildcard path
    /// segment (empty = the root, needs the trailing slash), same per-segment encoding as
    /// `browseURL` / `fetchMetadata`.
    func fetchUsage(serverURL: URL, path: String) async throws -> StorageUsage {
        let url = Self.appendingPathSegments(of: path, to: serverURL.appendingPathComponent(APIPath.usage))
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: StorageUsage.self)
    }

    func volumes(serverURL: URL) async throws -> [Volume] {
        let url = serverURL.appendingPathComponent(APIPath.volumes)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: [Volume].self)
    }

    /// `GET /api/browse/*`. An empty path browses the root and must still end in a
    /// trailing slash (`/api/browse/`); non-empty paths are split and each segment
    /// percent-encoded individually so names containing `/`-unsafe characters survive.
    static func browseURL(serverURL: URL, path: String) -> URL {
        appendingPathSegments(of: path, to: serverURL.appendingPathComponent(APIPath.browse))
    }
}
