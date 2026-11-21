import CoreModels
import Foundation
import NetworkClient

/// The person's own trash, `backend/src/routes/trash.js`: list it, look inside a deleted folder or
/// file, restore in place or into a chosen folder, and delete for good. Nothing here is cached: the
/// server forbids storing these answers.
extension FilesService {
    /// The most ids or entry paths the server takes in one request (`MAX_IDS`).
    static let trashBatchLimit = 1000

    private struct RestoreBody: Encodable {
        let ids: [String]?
        let paths: [String]?
        let destination: String?
        let shares: ShareLinkChoice
    }

    private struct PurgeBody: Encodable {
        let ids: [String]
        let shouldForgetUnavailable: Bool?

        private enum CodingKeys: String, CodingKey {
            case ids
            case shouldForgetUnavailable = "forgetUnavailable"
        }
    }

    private static func trashItemURL(_ serverURL: URL, id: String, component: String) -> URL {
        let base = serverURL.appendingPathComponent(APIPath.trashItems)
        return URL(string: base.absoluteString + "/" + encodedSegment(id) + "/" + component) ?? base
    }

    /// `GET /api/trash`.
    func fetchTrash(serverURL: URL) async throws -> TrashListing {
        let request = Self.makeRequest(url: serverURL.appendingPathComponent(APIPath.trash), method: .get)
        return try await sendReportingMessage(request, decoding: TrashListing.self)
    }

    func fetchTrashEntries(serverURL: URL, itemID: String, path: String) async throws -> TrashFolderListing {
        let base = Self.trashItemURL(serverURL, id: itemID, component: APIPath.Component.entries)
        let url = try Self.url(base, items: [(QueryKey.path, path)])
        return try await sendReportingMessage(
            Self.makeRequest(url: url, method: .get),
            decoding: TrashFolderListing.self
        )
    }

    /// `GET /api/trash/items/:id/text?path=`: JSON `{ name, size, modifiedAt, content }`.
    func fetchTrashText(serverURL: URL, itemID: String, path: String) async throws -> TrashText {
        let base = Self.trashItemURL(serverURL, id: itemID, component: APIPath.Component.text)
        let url = try Self.url(base, items: [(QueryKey.path, path)])
        return try await sendReportingMessage(Self.makeRequest(url: url, method: .get), decoding: TrashText.self)
    }

    /// `POST /api/trash/restore` or `/api/trash/items/:id/restore`, or with a `destination` the
    /// streamed routes that restore into that folder. Sent in batches the server accepts; the answers are joined.
    func restoreTrash(
        serverURL: URL,
        target: TrashTarget,
        destination: String?,
        shares: ShareLinkChoice,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> TrashActionResult {
        var entries: [TrashActionResult.Entry] = []
        for batch in Self.trashBatches(target) {
            let url: URL
            let body: RestoreBody
            switch batch {
            case let .items(ids):
                let route = destination == nil ? APIPath.trashRestore : APIPath.trashRestoreTo
                url = serverURL.appendingPathComponent(route)
                body = RestoreBody(ids: ids, paths: nil, destination: destination, shares: shares)
            case let .entries(itemID, paths):
                let component = destination == nil ? APIPath.Component.restore : APIPath.Component.restoreTo
                url = Self.trashItemURL(serverURL, id: itemID, component: component)
                body = RestoreBody(ids: nil, paths: paths, destination: destination, shares: shares)
            }
            var request = Self.makeRequest(url: url, method: .post, isMutation: true)
            request.setJSONContentType()
            request.httpBody = try Self.encode(body)
            let result = destination == nil
                ? try await sendReportingMessage(request, decoding: TrashActionResult.self)
                : try await sendStreamedOperation(request, decoding: TrashActionResult.self, onProgress: onProgress)
            entries += result.items
        }
        return TrashActionResult(items: entries)
    }

    /// `POST /api/trash/delete`. `forgetUnavailable` lets an administrator drop the record of an item
    /// whose volume is gone; the server ignores it for anyone else.
    func purgeTrash(serverURL: URL, ids: [String], forgetUnavailable: Bool) async throws -> TrashActionResult {
        var entries: [TrashActionResult.Entry] = []
        for batch in Self.trashBatches(.items(ids)) {
            guard case let .items(batchIDs) = batch else { continue }
            var request = Self.makeRequest(
                url: serverURL.appendingPathComponent(APIPath.trashDelete),
                method: .post,
                isMutation: true
            )
            request.setJSONContentType()
            request.httpBody = try Self.encode(PurgeBody(
                ids: batchIDs,
                shouldForgetUnavailable: forgetUnavailable
                    ? true
                    : nil
            ))
            entries += try await sendReportingMessage(request, decoding: TrashActionResult.self).items
        }
        return TrashActionResult(items: entries)
    }

    func emptyTrash(serverURL: URL) async throws -> TrashEmptySummary {
        let request = Self.makeRequest(
            url: serverURL.appendingPathComponent(APIPath.trashEmpty),
            method: .post,
            isMutation: true
        )
        return try await sendReportingMessage(request, decoding: TrashEmptySummary.self)
    }

    static func trashBatches(_ target: TrashTarget) -> [TrashTarget] {
        switch target {
        case let .items(ids):
            stride(from: 0, to: ids.count, by: trashBatchLimit).map {
                .items(Array(ids[$0 ..< min($0 + trashBatchLimit, ids.count)]))
            }
        case let .entries(itemID, paths):
            stride(from: 0, to: paths.count, by: trashBatchLimit).map {
                .entries(itemID: itemID, paths: Array(paths[$0 ..< min($0 + trashBatchLimit, paths.count)]))
            }
        }
    }
}
