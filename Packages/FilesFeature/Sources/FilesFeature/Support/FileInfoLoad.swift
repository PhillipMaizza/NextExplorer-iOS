import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

enum FileInfoLoad {
    static func effect<Action>(
        for item: FileItem,
        serverURL: URL,
        settle: Duration? = nil,
        metadata: @escaping @Sendable (Result<FileMetadata, FilesClientError>) -> Action,
        usage: @escaping @Sendable (Result<StorageUsage, FilesClientError>) -> Action
    ) -> Effect<Action> {
        @Dependency(\.filesClient) var filesClient
        @Dependency(\.continuousClock) var clock
        let path = item.id
        let loadMetadata = Effect<Action>.run { send in
            if let settle {
                try await clock.sleep(for: settle)
            }
            try await send(metadata(apiResult { try await filesClient.fetchMetadata(serverURL, path) }))
        }
        guard item.isDirectory else { return loadMetadata }
        return .merge(loadMetadata, .run { send in
            if let settle {
                try await clock.sleep(for: settle)
            }
            try await send(usage(apiResult { try await filesClient.fetchUsage(serverURL, path) }))
        })
    }
}
