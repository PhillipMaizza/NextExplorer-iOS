import CoreModels
import Foundation

extension FilesService {
    /// The most paths one folder size batch call takes; the server drops the rest.
    static let folderSizeBatchLimit = 500

    /// The folder size batch route (`backend/src/routes/folderSize.js`): the indexed size of each
    /// folder, in chunks of the server's cap. The server answers one entry per requested path, in
    /// order, but the entry's own `path` is the resolved one, so the result is keyed by the path
    /// that was asked for. The route is a 404 while the feature is off, so callers gate on
    /// `ServerFeatures.folderSizeMode`.
    func folderSizes(serverURL: URL, paths: [String]) async throws -> [String: FolderSize] {
        var sizes: [String: FolderSize] = [:]
        let url = serverURL.appendingPathComponent(APIPath.folderSize).appendingPathComponent(APIPath.Component.batch)
        for start in stride(from: 0, to: paths.count, by: Self.folderSizeBatchLimit) {
            let chunk = Array(paths[start ..< min(start + Self.folderSizeBatchLimit, paths.count)])
            var request = Self.makeRequest(url: url, method: .post)
            request.setJSONContentType()
            do {
                request.httpBody = try JSONEncoder().encode(FolderSizeBatchBody(paths: chunk))
            } catch {
                throw FilesClientError.decoding(error.localizedDescription)
            }
            let results = try await send(request, decoding: FolderSizeBatchEnvelope.self).results
            guard results.count == chunk.count else { continue }
            for (path, entry) in zip(chunk, results) {
                sizes[path] = entry
            }
        }
        return sizes
    }

    /// The folder size refresh route, one folder path appended: asks the server to scan one folder's subtree again, for
    /// a folder changed outside NextExplorer. The answer is a 202 with the entry as it is now, while
    /// the scan carries on in the background, so the caller reads the size again a moment later.
    /// A refusal (excluded folder, indexer not ready, too many pending scans) comes back as an error.
    func refreshFolderSize(serverURL: URL, path: String) async throws -> FolderSize {
        let base = serverURL.appendingPathComponent(APIPath.folderSize)
            .appendingPathComponent(APIPath.Component.refresh)
        let url = Self.appendingPathSegments(of: path, to: base)
        let request = Self.makeRequest(url: url, method: .post, isMutation: true)
        return try await send(request, decoding: FolderSize.self)
    }
}
