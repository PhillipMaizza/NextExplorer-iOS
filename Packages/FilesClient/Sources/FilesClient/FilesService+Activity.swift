import CoreModels
import Foundation
import NetworkClient

/// The activity log routes, `backend/src/routes/activity.js`. Admin only.
extension FilesService {
    private enum ActivityQuery {
        static let limit = 100
    }

    /// `GET /api/activity`. The server pages by the moment of the last row, so `before` is the
    /// previous page's `nextBefore`, never an offset.
    func fetchActivity(serverURL: URL, filter: ActivityFilter, before: String?) async throws -> ActivityPage {
        var items: [(String, String)] = [("limit", String(ActivityQuery.limit))]
        if let action = filter.action, !action.isEmpty {
            items.append(("action", action))
        }
        if let outcome = filter.outcome {
            items.append(("outcome", outcome.rawValue))
        }
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items.append(("q", query))
        }
        if let before, !before.isEmpty {
            items.append(("before", before))
        }

        let url = try Self.url(serverURL: serverURL, path: APIPath.activity, items: items)
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: ActivityPage.self)
    }

    /// `DELETE /api/activity`: empties the log.
    func clearActivity(serverURL: URL) async throws {
        let request = Self.makeRequest(url: serverURL.appendingPathComponent(APIPath.activity), method: .delete, isMutation: true)
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }
}
