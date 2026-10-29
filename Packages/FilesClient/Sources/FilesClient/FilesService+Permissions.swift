import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    /// `GET /api/permissions/*`, confirmed against `backend/src/routes/permissions.js`: one
    /// wildcard path segment, same per-segment encoding as `fetchMetadata` / `fetchUsage`. A
    /// denied path 403s with the server's denial reason, worth surfacing verbatim.
    func fetchPermissions(serverURL: URL, path: String) async throws -> FilePermissions {
        let url = Self.appendingPathSegments(of: path, to: serverURL.appendingPathComponent(APIPath.permissions))
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: FilePermissions.self)
    }

    /// `GET /api/versions?path=`: the path goes in the query, unlike the path routes.
    func fetchVersions(serverURL: URL, path: String) async throws -> FileVersionHistory {
        var components = URLComponents(url: serverURL.appendingPathComponent(APIPath.versions), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components?.url else { throw FilesClientError.decoding("Could not build versions URL.") }
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: FileVersionHistory.self)
    }

    /// `POST /api/versions/:id/restore` with `{ path }`.
    func restoreVersion(serverURL: URL, path: String, versionID: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.versions).appendingPathComponent(versionID).appendingPathComponent("restore")
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(VersionPathBody(path: path))
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    /// `POST /api/permissions/chmod`: `{ path, mode, recursive }`. The server enforces
    /// `mode` matching `/^[0-7]{3}$/`; `recursive` only does anything on a directory.
    func changePermissions(serverURL: URL, path: String, mode: String, recursive: Bool) async throws {
        let url = serverURL.appendingPathComponent(APIPath.permissionsChmod)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ChmodBody(path: path, mode: mode, recursive: recursive))
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    /// `POST /api/permissions/chown`: `{ path, owner?, group? }` — a nil field is omitted, and
    /// the server rejects a body carrying neither.
    func changeOwnership(serverURL: URL, path: String, owner: String?, group: String?) async throws {
        let url = serverURL.appendingPathComponent(APIPath.permissionsChown)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ChownBody(path: path, owner: owner, group: group))
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }
}
