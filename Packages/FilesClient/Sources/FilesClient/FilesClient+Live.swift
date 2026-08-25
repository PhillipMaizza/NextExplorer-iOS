import Dependencies
import Foundation
import NetworkClient

extension FilesClient {
    public static func live(networkClient: NetworkClient) -> FilesClient {
        let service = FilesService(networkClient: networkClient)
        return FilesClient(
            browse: { serverURL, path in
                try await service.browse(serverURL: serverURL, path: path)
            },
            search: { serverURL, path, query, limit in
                try await service.search(serverURL: serverURL, path: path, query: query, limit: limit)
            },
            favorites: { serverURL in
                try await service.favorites(serverURL: serverURL)
            },
            volumes: { serverURL in
                try await service.volumes(serverURL: serverURL)
            },
            fetchPreferences: { serverURL in
                try await service.fetchPreferences(serverURL: serverURL)
            },
            updatePreference: { serverURL, key, value in
                try await service.updatePreference(serverURL: serverURL, key: key, value: value)
            }
        )
    }
}

extension FilesClient: DependencyKey {
    public static var liveValue: FilesClient {
        @Dependency(\.networkClient) var networkClient
        return .live(networkClient: networkClient)
    }
}

extension DependencyValues {
    public var filesClient: FilesClient {
        get { self[FilesClient.self] }
        set { self[FilesClient.self] = newValue }
    }
}
