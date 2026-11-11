import CoreModels
import Foundation
import NetworkClient

/// The administrator's list of every file that has a history, `backend/src/routes/versionsAdmin.js`.
/// A history is named here by its own id, since the ones worth finding include files that no longer
/// exist.
extension FilesService {
    private struct DeleteVersionsBody: Encodable {
        let ids: [String]?
        let all: Bool?
    }

    /// One history's address. The id is encoded as a single segment, so one holding a slash
    /// cannot point at another route.
    private static func versionsAdminURL(_ serverURL: URL, id: String) -> URL {
        let segment = Self.encodedSegment(id)
        return URL(string: serverURL.appendingPathComponent(APIPath.versionsAdminFiles).absoluteString + "/" + segment)
            ?? serverURL.appendingPathComponent(APIPath.versionsAdminFiles)
    }

    /// `GET /api/versions/admin/files`.
    func fetchVersionedFiles(serverURL: URL, filter: VersionedFilesFilter, offset: Int, limit: Int) async throws -> VersionedFilesPage {
        var items: [(String, String)] = [("sort", filter.sort.rawValue), ("limit", String(limit))]
        if let zoneID = filter.zoneID, !zoneID.isEmpty {
            items.append(("zone", zoneID))
        }
        if let state = filter.state {
            items.append(("state", state.rawValue))
        }
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items.append(("q", query))
        }
        if offset > 0 {
            items.append(("offset", String(offset)))
        }

        let url = try Self.url(serverURL: serverURL, path: APIPath.versionsAdminFiles, items: items)
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: VersionedFilesPage.self)
    }

    /// `GET /api/versions/admin/files/:id`.
    func fetchVersionedFile(serverURL: URL, id: String) async throws -> VersionedFileDetail {
        let url = Self.versionsAdminURL(serverURL, id: id)
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: VersionedFileDetail.self)
    }

    /// `POST /api/versions/admin/files/:id/delete` with `{ ids }`, or `{ all: true }` when `ids` is nil.
    func deleteVersionsOfFile(serverURL: URL, id: String, ids: [String]?) async throws -> VersionsDeletion {
        let url = Self.versionsAdminURL(serverURL, id: id).appendingPathComponent("delete")
        var request = Self.makeRequest(url: url, method: .post, isMutation: true)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ids.map { DeleteVersionsBody(ids: $0, all: nil) } ?? DeleteVersionsBody(ids: nil, all: true))
        return try await sendReportingMessage(request, decoding: VersionsDeletion.self)
    }
}
