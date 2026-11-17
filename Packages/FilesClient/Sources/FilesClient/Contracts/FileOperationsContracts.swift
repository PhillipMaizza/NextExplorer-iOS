import CoreModels
import Foundation

/// Wire types for the file-operation endpoints (rename, folder, zip, editor, delete, transfer).
/// See `FilesService+FileOperations.swift`.
extension FilesService {
    struct RenameItemBody: Encodable {
        let path: String
        let name: String
        let newName: String
    }

    struct RenameItemEnvelope: Decodable {
        let item: FileItem
    }

    /// The body of both `POST /api/files/folder` and `POST /api/files/file`: the parent folder
    /// and the new item's name.
    struct CreateFolderBody: Encodable {
        let path: String
        let name: String
    }

    struct CreateFolderEnvelope: Decodable {
        let item: FileItem
    }

    struct EditorPathBody: Encodable {
        let path: String
    }

    struct EditorContentEnvelope: Decodable {
        let content: String
    }

    struct EditorSaveBody: Encodable {
        let path: String
        let content: String
    }

    struct ExtractZipBody: Encodable {
        let path: String
    }

    struct ExtractZipEnvelope: Decodable {
        let item: FileItem
    }

    struct CompressItemBody: Encodable {
        struct Item: Encodable {
            let name: String
            let path: String
        }

        let items: [Item]
        let destination: String
    }

    struct OperationStreamEvent: Decodable {
        static let doneType = "done"
        static let errorType = "error"
        static let progressType = "progress"

        let type: String?
        let message: String?
        /// A transfer's progress (`copiedBytes` of `totalBytes`), or an archive's (`percent`).
        let copiedBytes: Int64?
        let totalBytes: Int64?
        let percent: Double?

        /// How far a `progress` event says the work is, from 0 to 1; `nil` for any other event or
        /// one with nothing to measure yet.
        var fraction: Double? {
            guard type == Self.progressType else { return nil }
            if let totalBytes, totalBytes > 0, let copiedBytes {
                return min(max(Double(copiedBytes) / Double(totalBytes), 0), 1)
            }
            return percent.map { min(max($0 / 100, 0), 1) }
        }
    }

    struct CompressItemEnvelope: Decodable {
        let item: FileItem
    }

    struct TransferItemsBody: Encodable {
        struct Item: Encodable {
            let path: String
            let name: String
        }

        let items: [Item]
        let destination: String
    }

    struct DeleteItemsBody: Encodable {
        struct Item: Encodable {
            let path: String
            let name: String
            let kind: String
        }

        let items: [Item]
        /// Sent only as `true`: left out, the server uses the trash when it has one.
        var permanent: Bool?
    }
}
