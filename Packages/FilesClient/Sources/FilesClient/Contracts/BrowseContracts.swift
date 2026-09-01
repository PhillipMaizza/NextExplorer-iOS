import CoreModels
import Foundation

/// Wire types for the Browse/search endpoints. See `FilesService+Browse.swift`.
extension FilesService {
    struct SearchEnvelope: Decodable {
        let items: [SearchResultItem]
    }

    struct ThumbnailEnvelope: Decodable {
        let thumbnail: String
    }
}
