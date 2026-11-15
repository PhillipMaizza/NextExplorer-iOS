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
        /// `true` while the server still makes the thumbnail (a video's first frame takes ffmpeg a
        /// moment): the empty `thumbnail` then means "not yet", not "none".
        let pending: Bool?
        let retryAfterMs: Int?
    }
}
