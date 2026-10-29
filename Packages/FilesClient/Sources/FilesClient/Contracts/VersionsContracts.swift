import Foundation

/// Wire types for the Versions endpoints. See `FilesService+Versions.swift`.
extension FilesService {
    struct VersionPathBody: Encodable {
        let path: String
    }

    struct VersionCopyBody: Encodable {
        let path: String
        let destination: String
    }

    /// `PATCH /api/versions/:id`: a field left nil is omitted, so it stays as it is. An empty
    /// `label` clears the name (the server trims it to null).
    struct VersionUpdateBody: Encodable {
        let path: String
        let label: String?
        let pinned: Bool?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encodeIfPresent(pinned, forKey: .pinned)
        }

        private enum CodingKeys: String, CodingKey {
            case path, label, pinned
        }
    }

    struct VersionDeleteBody: Encodable {
        let path: String
        let ids: [String]?
        let all: Bool
    }

    struct VersionCopyResponse: Decodable {
        let path: String
    }
}
