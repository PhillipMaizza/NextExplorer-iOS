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
            addFavorite: { serverURL, path in
                try await service.addFavorite(serverURL: serverURL, path: path)
            },
            removeFavorite: { serverURL, path in
                try await service.removeFavorite(serverURL: serverURL, path: path)
            },
            volumes: { serverURL in
                try await service.volumes(serverURL: serverURL)
            },
            fetchPreferences: { serverURL in
                try await service.fetchPreferences(serverURL: serverURL)
            },
            updatePreference: { serverURL, key, value in
                try await service.updatePreference(serverURL: serverURL, key: key, value: value)
            },
            renameItem: { serverURL, item, newName in
                try await service.renameItem(serverURL: serverURL, item: item, newName: newName)
            },
            deleteItems: { serverURL, items in
                try await service.deleteItems(serverURL: serverURL, items: items)
            },
            fetchMetadata: { serverURL, path in
                try await service.fetchMetadata(serverURL: serverURL, path: path)
            },
            thumbnailURL: { serverURL, path in
                try await service.thumbnailURL(serverURL: serverURL, path: path)
            },
            previewFile: { serverURL, item in
                try await service.previewFile(serverURL: serverURL, item: item)
            },
            fetchTextContent: { serverURL, path in
                try await service.fetchTextContent(serverURL: serverURL, path: path)
            },
            saveTextContent: { serverURL, path, content in
                try await service.saveTextContent(serverURL: serverURL, path: path, content: content)
            },
            extractZip: { serverURL, item in
                try await service.extractZip(serverURL: serverURL, item: item)
            },
            downloadRawFile: { serverURL, item in
                try await service.downloadRawFile(serverURL: serverURL, item: item)
            },
            compressItem: { serverURL, item in
                try await service.compressItem(serverURL: serverURL, item: item)
            },
            createShareLink: { serverURL, request in
                try await service.createShareLink(serverURL: serverURL, request: request)
            },
            mySharedLinks: { serverURL in
                try await service.shareLinks(serverURL: serverURL, sharedWithMe: false)
            },
            sharedWithMeLinks: { serverURL in
                try await service.shareLinks(serverURL: serverURL, sharedWithMe: true)
            },
            deleteShareLink: { serverURL, shareID in
                try await service.deleteShareLink(serverURL: serverURL, shareID: shareID)
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
