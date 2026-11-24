import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    func listArchive(serverURL: URL, archive: FileItem, inside: String) async throws -> ArchiveListing {
        let url = try Self.url(
            serverURL: serverURL,
            path: APIPath.archiveList,
            items: [(QueryKey.path, archive.id), (QueryKey.inside, inside)]
        )
        return try await send(Self.makeRequest(url: url, method: .get), decoding: ArchiveListing.self)
    }

    func downloadArchiveEntry(serverURL: URL, archive: FileItem, entryPath: String) async throws -> URL {
        let url = try Self.url(
            serverURL: serverURL,
            path: APIPath.archiveEntry,
            items: [(QueryKey.path, archive.id), (QueryKey.entry, entryPath)]
        )
        let downloadedURL: URL
        let response: HTTPURLResponse
        do {
            (downloadedURL, response) = try await networkClient.downloadWithProgress(
                Self.makeRequest(url: url, method: .get)
            ) { _ in }
        } catch {
            throw Self.mapTransportError(error)
        }
        do {
            try Self.validate(response)
        } catch {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw error
        }
        return downloadedURL
    }

    func extractArchiveEntries(serverURL: URL, archive: FileItem, entryPaths: [String]) async throws -> [FileItem] {
        let url = serverURL.appendingPathComponent(APIPath.archiveExtract)
        var request = Self.makeRequest(url: url, method: .post, isMutation: true)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ArchiveExtractBody(path: archive.id, entries: entryPaths))
        return try await sendStreamedOperation(request, decoding: ArchiveExtractEnvelope.self).items
    }
}
