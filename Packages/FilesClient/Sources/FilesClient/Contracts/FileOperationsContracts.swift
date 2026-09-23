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

    struct ArchiveStreamEvent: Decodable {
        static let doneType = "done"
        static let errorType = "error"

        let type: String?
        let message: String?
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
    }
}
