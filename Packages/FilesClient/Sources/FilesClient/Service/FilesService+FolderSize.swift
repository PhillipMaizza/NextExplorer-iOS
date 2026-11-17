import CoreModels
import Foundation

extension FilesService {
    /// The most paths one folder size batch call takes; the server drops the rest.
    static let folderSizeBatchLimit = 500

    /// The folder size batch route (`backend/src/routes/folderSize.js`): the indexed size of each
    /// folder, one request for the first 500 paths, as the web client does. The server answers one
    /// entry per requested path, in order, so the result is keyed by the path that was asked for
    /// (the entry's own path is the resolved one). The route is a 404 while the feature is off, so
    /// callers gate on `ServerFeatures.folderSizeMode`.
    func folderSizes(serverURL: URL, paths: [String]) async throws -> [String: FolderSize] {
        let asked = Array(paths.prefix(Self.folderSizeBatchLimit))
        guard !asked.isEmpty else { return [:] }
        let url = serverURL.appendingPathComponent(APIPath.folderSize).appendingPathComponent(APIPath.Component.batch)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(FolderSizeBatchBody(paths: asked))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let results = try await send(request, decoding: FolderSizeBatchEnvelope.self).results
        return Dictionary(zip(asked, results), uniquingKeysWith: { first, _ in first })
    }

    /// The folder size refresh route, one folder path appended: asks the server to scan that folder
    /// again, for a folder changed outside NextExplorer. The answer is a 202 with the entry as it is
    /// now, while the scan carries on in the background, so the caller reads the size again a moment
    /// later. A refusal (excluded folder, indexer not ready, too many pending scans) is an error.
    func refreshFolderSize(serverURL: URL, path: String) async throws -> FolderSize {
        let base = serverURL.appendingPathComponent(APIPath.folderSize)
            .appendingPathComponent(APIPath.Component.refresh)
        let url = Self.appendingPathSegments(of: path, to: base)
        let request = Self.makeRequest(url: url, method: .post, isMutation: true)
        return try await send(request, decoding: FolderSize.self)
    }
}
