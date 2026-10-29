import CoreModels
import Foundation
import NetworkClient

/// The file history endpoints, `backend/src/routes/versions.js`. Every route names the file
/// by its path (in the query for reads, in the body for writes) and the version by its id.
extension FilesService {
    /// `GET /api/versions?path=`.
    func fetchVersions(serverURL: URL, path: String) async throws -> FileVersionHistory {
        let request = try Self.makeRequest(url: Self.versionsURL(serverURL, query: path), method: .get)
        return try await sendReportingMessage(request, decoding: FileVersionHistory.self)
    }

    /// `POST /api/versions/:id/restore` with `{ path }`.
    func restoreVersion(serverURL: URL, path: String, versionID: String) async throws {
        try await sendVersionWrite(serverURL, versionID, "restore", method: .post, body: VersionPathBody(path: path))
    }

    /// `GET /api/versions/:id/content?path=`, streamed to disk and moved to `destination`.
    func downloadVersion(serverURL: URL, path: String, versionID: String, to destination: URL) async throws {
        let base = serverURL.appendingPathComponent(APIPath.versions).appendingPathComponent(versionID).appendingPathComponent("content")
        let request = try Self.makeRequest(url: Self.versionsURL(base, query: path, appendingAPIPath: false), method: .get)
        let downloadedURL: URL
        let response: HTTPURLResponse
        do {
            (downloadedURL, response) = try await networkClient.download(request)
        } catch {
            throw Self.mapTransportError(error)
        }
        defer { try? FileManager.default.removeItem(at: downloadedURL) }
        try Self.validate(response)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: downloadedURL, to: destination)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// `POST /api/versions/:id/copy` with `{ path, destination }`: a new file in `destination`,
    /// named after the version. Returns the new file's path.
    func copyVersion(serverURL: URL, path: String, versionID: String, destination: String) async throws -> String {
        var request = Self.makeRequest(url: Self.versionURL(serverURL, versionID, "copy"), method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(VersionCopyBody(path: path, destination: destination))
        return try await sendReportingMessage(request, decoding: VersionCopyResponse.self).path
    }

    /// `PATCH /api/versions/:id` with `{ path, label?, pinned? }`.
    func updateVersion(serverURL: URL, path: String, versionID: String, label: String?, pinned: Bool?) async throws -> FileVersion {
        var request = Self.makeRequest(url: Self.versionURL(serverURL, versionID, nil), method: .patch)
        request.setJSONContentType()
        request.httpBody = try Self.encode(VersionUpdateBody(path: path, label: label, pinned: pinned))
        return try await sendReportingMessage(request, decoding: FileVersion.self)
    }

    /// `POST /api/versions/delete` with `{ path, ids }` or `{ path, all: true }`.
    func deleteVersions(serverURL: URL, path: String, ids: [String]?, all: Bool) async throws {
        var request = Self.makeRequest(url: serverURL.appendingPathComponent(APIPath.versions).appendingPathComponent("delete"), method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(VersionDeleteBody(path: path, ids: all ? nil : ids, all: all))
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    private func sendVersionWrite(
        _ serverURL: URL, _ versionID: String, _ action: String?, method: HTTPMethod, body: some Encodable
    ) async throws {
        var request = Self.makeRequest(url: Self.versionURL(serverURL, versionID, action), method: method)
        request.setJSONContentType()
        request.httpBody = try Self.encode(body)
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    private static func versionURL(_ serverURL: URL, _ versionID: String, _ action: String?) -> URL {
        let url = serverURL.appendingPathComponent(APIPath.versions).appendingPathComponent(versionID)
        return action.map { url.appendingPathComponent($0) } ?? url
    }

    private static func versionsURL(_ base: URL, query path: String, appendingAPIPath: Bool = true) throws -> URL {
        let url = appendingAPIPath ? base.appendingPathComponent(APIPath.versions) : base
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let built = components?.url else { throw FilesClientError.decoding("Could not build versions URL.") }
        return built
    }
}
