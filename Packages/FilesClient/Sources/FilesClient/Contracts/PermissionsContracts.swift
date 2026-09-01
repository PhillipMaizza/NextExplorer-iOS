import CoreModels
import Foundation

/// Wire types for the Permissions endpoints. See `FilesService+Permissions.swift`.
extension FilesService {
    struct ChmodBody: Encodable {
        let path: String
        let mode: String
        let recursive: Bool
    }

    /// A nil `owner`/`group` is left out by the synthesized encoder (`encodeIfPresent`), which
    /// is exactly what the server wants — it treats a missing key as "leave this unchanged".
    struct ChownBody: Encodable {
        let path: String
        let owner: String?
        let group: String?
    }
}
