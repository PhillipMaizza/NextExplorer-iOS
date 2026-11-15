import CoreModels
import FilesClient
import Foundation

extension FilesClient {
    /// The local file Quick Look shows for a document. Word documents aren't in the server's
    /// `PREVIEWABLE_EXTENSIONS`, so `GET /api/preview` refuses them with 415 and they come down
    /// through the unrestricted download endpoint instead.
    func previewDocument(_ serverURL: URL, _ item: FileItem) async throws -> URL {
        item.isOfficeDocument
            ? try await downloadRawFile(serverURL, item)
            : try await previewFile(serverURL, item)
    }
}
