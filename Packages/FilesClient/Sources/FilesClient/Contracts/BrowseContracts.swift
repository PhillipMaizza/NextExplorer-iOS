import CoreModels
import Foundation

/// Wire types for the Browse/search endpoints. See `FilesService+Browse.swift`.
extension FilesService {
    struct SearchEnvelope: Decodable {
        let items: [SearchResultItem]
        let truncated: Bool?
        let limit: Int?
        let complete: Bool?
    }

    struct ThumbnailEnvelope: Decodable {
        let thumbnail: String
    }
}
