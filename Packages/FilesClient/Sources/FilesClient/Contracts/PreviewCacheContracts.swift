import CoreModels
import Foundation

/// Wire types for the preview/download endpoints. See `FilesService+PreviewCache.swift`.
extension FilesService {
    struct DownloadRawFileBody: Encodable {
        let path: String
    }
}
