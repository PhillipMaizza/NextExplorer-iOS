import ComposableArchitecture
import CoreModels
import Foundation

extension BrowseFeature {
    func requestUploads(_ files: [PickedFile], destination: String, serverURL: URL) -> Effect<Action> {
        let folders = Set(files.compactMap { UploadedFolder.root(of: $0.fileName) })
        guard !folders.isEmpty else {
            return .send(.delegate(.uploadRequested(UploadedFolder.pending(files, destination: destination))))
        }
        let filesClient = filesClient
        return .run { send in
            var reserved: [String: String] = [:]
            for folder in folders.sorted() {
                reserved[folder] = await (try? filesClient.reserveFolderUpload(serverURL, destination, folder)) ??
                    folder
            }
            let renamed = files.map { UploadedFolder.renamed($0, reserved: reserved) }
            await send(.delegate(.uploadRequested(UploadedFolder.pending(renamed, destination: destination))))
        }
    }
}

enum UploadedFolder {
    static let separator: Character = "/"

    static func root(of fileName: String) -> String? {
        let parts = fileName.split(separator: separator, maxSplits: 1)
        return parts.count == 2 ? String(parts[0]) : nil
    }

    static func renamed(_ file: PickedFile, reserved: [String: String]) -> PickedFile {
        guard let root = root(of: file.fileName), let target = reserved[root], target != root else { return file }
        let rest = file.fileName.dropFirst(root.count)
        return PickedFile(id: file.id, fileURL: file.fileURL, fileName: target + rest, size: file.size)
    }

    static func pending(_ files: [PickedFile], destination: String) -> [PendingUpload] {
        files.map {
            PendingUpload(
                id: $0.id,
                fileURL: $0.fileURL,
                fileName: $0.fileName,
                destination: destination,
                size: $0.size
            )
        }
    }
}
