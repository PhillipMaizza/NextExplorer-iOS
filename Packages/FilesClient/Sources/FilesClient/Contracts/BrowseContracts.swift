import CoreModels
import Foundation

/// Wire types for the Browse/search endpoints. See `FilesService+Browse.swift`.
extension FilesService {
    struct FolderSizeBatchBody: Encodable { let paths: [String] }

    struct FolderSizeBatchEnvelope: Decodable {
        let results: [FolderSize]
    }

    struct SearchEnvelope: Decodable {
        let items: [SearchResultItem]
        let isTruncated: Bool?
        let limit: Int?
        let isComplete: Bool?

        private enum CodingKeys: String, CodingKey {
            case items, limit
            case isTruncated = "truncated"
            case isComplete = "complete"
        }
    }

    struct ThumbnailEnvelope: Decodable {
        let thumbnail: String
        /// `true` while the server still makes the thumbnail (a video's first frame takes ffmpeg a
        /// moment): the empty `thumbnail` then means "not yet", not "none".
        let isPending: Bool?
        let retryAfterMs: Int?

        private enum CodingKeys: String, CodingKey {
            case thumbnail, retryAfterMs
            case isPending = "pending"
        }
    }
}
