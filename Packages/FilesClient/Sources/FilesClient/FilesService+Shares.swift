import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    /// `POST /api/shares`, confirmed against `backend/src/routes/shares.js` +
    /// `sharesService.js`. `userIds` is only meaningful when `sharingType == "users"` (the
    /// server ignores it otherwise); `expiresAt` must be a future ISO date or the server 400s.
    /// The 201 body is the share row flattened together with `shareUrl` / `directFileUrl`.
    func createShareLink(serverURL: URL, request: CreateShareLinkRequest) async throws -> CreatedShare {
        let url = serverURL.appendingPathComponent(APIPath.shares)
        var httpRequest = Self.makeRequest(url: url, method: .post)
        httpRequest.setJSONContentType()
        let body = CreateShareBody(
            sourcePath: request.sourcePath,
            label: request.label,
            accessMode: request.accessMode.rawValue,
            sharingType: request.target.rawValue,
            password: request.password,
            userIds: request.target == .users ? request.userIds : [],
            expiresAt: request.expiresAt.map(Self.formatShareExpiry)
        )
        httpRequest.httpBody = try Self.encode(body)
        return try await sendReportingMessage(httpRequest, decoding: CreatedShare.self)
    }

    /// `GET /api/shares` (owner) and `GET /api/shares/shared-with-me` (recipient), both
    /// wrapped `{ shares: [...] }`. The recipient variant omits `sourcePath`/`sourceSpace`
    /// and adds `sourceName`.
    func shareLinks(serverURL: URL, sharedWithMe: Bool) async throws -> [Share] {
        let url = sharedWithMe
            ? serverURL.appendingPathComponent(APIPath.sharesSharedWithMe)
            : serverURL.appendingPathComponent(APIPath.shares)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: ShareLinksEnvelope.self).shares
    }

    /// `GET /api/users/shareable`, confirmed against `backend/src/routes/users.js` +
    /// `services/users/management.js`: every user but the caller as
    /// `{id, email, username, displayName}` (no `roles`), wrapped `{ users: [...] }`.
    func shareableUsers(serverURL: URL) async throws -> [User] {
        let url = serverURL.appendingPathComponent(APIPath.usersShareable)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: ShareableUsersEnvelope.self).users
    }

    /// `GET /api/share/<token>/info`, confirmed against `backend/src/routes/shares.js`:
    /// unauthenticated public metadata for a share link. The token is a single path segment.
    func resolveShareLink(serverURL: URL, token: String) async throws -> ShareInfo {
        let url = serverURL
            .appendingPathComponent(APIPath.share)
            .appendingPathComponent(token)
            .appendingPathComponent(APIPath.shareInfoComponent)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: ShareInfo.self)
    }

    /// `PUT /api/shares/:id`, confirmed against `backend/src/routes/shares.js` +
    /// `sharesService.updateShare`: owner-only, `'key' in body` semantics, returns the
    /// updated share unwrapped.
    func updateShareLink(serverURL: URL, shareID: String, request: UpdateShareRequest) async throws -> Share {
        let url = serverURL.appendingPathComponent(APIPath.shares).appendingPathComponent(shareID)
        var httpRequest = Self.makeRequest(url: url, method: .put)
        httpRequest.setJSONContentType()
        let body = UpdateShareBody(
            label: request.label,
            accessMode: request.accessMode.rawValue,
            sharingType: request.target.rawValue,
            expiresAt: request.expiresAt.map(Self.formatShareExpiry),
            userIds: request.target == .users ? request.userIds : nil,
            password: request.password
        )
        httpRequest.httpBody = try Self.encode(body)
        return try await sendReportingMessage(httpRequest, decoding: Share.self)
    }

    /// `DELETE /api/shares/:id` → 204, owner only.
    func deleteShareLink(serverURL: URL, shareID: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.shares).appendingPathComponent(shareID)
        let request = Self.makeRequest(url: url, method: .delete)
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// Share-expiry wire format is plain `withInternetDateTime` (no fractional seconds, unlike
    /// the decode path). Cached like `iso8601Formatter` — safe to format from concurrently.
    nonisolated(unsafe) private static let shareExpiryFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func formatShareExpiry(_ date: Date) -> String {
        shareExpiryFormatter.string(from: date)
    }
}
